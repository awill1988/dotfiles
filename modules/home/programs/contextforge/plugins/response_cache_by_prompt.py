# -*- coding: utf-8 -*-
"""Location: ./plugins/response_cache_by_prompt/response_cache_by_prompt.py
Copyright 2025
SPDX-License-Identifier: Apache-2.0
Authors: Mihai Criveti

Response Cache by Prompt Plugin.

Advisory approximate caching of tool results using cosine similarity over
selected string fields (e.g., "prompt", "input").

Because the plugin framework cannot short-circuit tool execution at pre-hook,
the plugin returns cache hit info via metadata in `tool_pre_invoke`, and writes
results at `tool_post_invoke`.

Eviction: LRU (least recently accessed) when max_entries is reached per tool.
TTL is optional — set to 0 to disable time-based expiration entirely.
"""

# Future
from __future__ import annotations

# Standard
from collections import defaultdict
from dataclasses import dataclass, field
import math
import time
from typing import Any, Dict, List, Optional, Set, Tuple

# Third-Party
from pydantic import BaseModel, Field

# First-Party
from mcpgateway.plugins.framework import (
    Plugin,
    PluginConfig,
    PluginContext,
    ToolPostInvokePayload,
    ToolPostInvokeResult,
    ToolPreInvokePayload,
    ToolPreInvokeResult,
)


def _tokenize(text: str) -> list[str]:
    """Tokenize text into lowercase words.

    Args:
        text: Input text to tokenize.

    Returns:
        List of lowercase tokens.
    """
    return [t for t in text.lower().split() if t]


def _vectorize(text: str) -> Dict[str, float]:
    """Convert text to L2-normalized word frequency vector.

    Args:
        text: Input text.

    Returns:
        Dictionary mapping tokens to normalized frequencies.
    """
    vec: Dict[str, float] = {}
    for tok in _tokenize(text):
        vec[tok] = vec.get(tok, 0.0) + 1.0
    # L2 normalize
    norm = math.sqrt(sum(v * v for v in vec.values())) or 1.0
    for k in list(vec.keys()):
        vec[k] /= norm
    return vec


def _cos_sim(a: Dict[str, float], b: Dict[str, float]) -> float:
    """Compute cosine similarity between two vectors.

    Args:
        a: First vector (token -> frequency mapping).
        b: Second vector (token -> frequency mapping).

    Returns:
        Cosine similarity score between 0.0 and 1.0.
    """
    if not a or not b:
        return 0.0
    if len(a) > len(b):
        a, b = b, a
    return sum(a.get(k, 0.0) * b.get(k, 0.0) for k in a.keys())


class ResponseCacheConfig(BaseModel):
    """Configuration for response cache by prompt similarity.

    Attributes:
        cacheable_tools: List of tool names to cache.
        fields: Argument fields to extract text from for similarity matching.
        ttl: Time-to-live in seconds (0 = no expiry, rely on LRU eviction).
        threshold: Minimum cosine similarity threshold for cache hits.
        max_entries: Maximum number of cache entries per tool.
    """

    cacheable_tools: List[str] = Field(default_factory=list)
    fields: List[str] = Field(default_factory=lambda: ["prompt", "input", "query"])
    ttl: int = 0
    threshold: float = 0.92
    max_entries: int = 1000


@dataclass
class _Entry:
    """Cache entry storing text, vector, result, and access metadata.

    Attributes:
        text: Original text that was cached.
        vec: Normalized vector representation of text.
        value: Cached result value.
        expires_at: Unix timestamp when entry expires (0.0 = never).
        last_accessed: Unix timestamp of last access (for LRU eviction).
        tokens: Set of tokens for fast filtering (optimization).
    """

    text: str
    vec: Dict[str, float]
    value: Any
    expires_at: float
    last_accessed: float
    tokens: set[str] = field(default_factory=set)


def _is_alive(entry: _Entry, now: float) -> bool:
    """Check whether a cache entry is still valid.

    Args:
        entry: Cache entry to check.
        now: Current unix timestamp.

    Returns:
        True if entry has no expiry or hasn't expired yet.
    """
    return entry.expires_at == 0.0 or entry.expires_at > now


class ResponseCacheByPromptPlugin(Plugin):
    """Approximate response cache keyed by prompt similarity with LRU eviction."""

    def __init__(self, config: PluginConfig) -> None:
        """Initialize the response cache plugin.

        Args:
            config: Plugin configuration.
        """
        super().__init__(config)
        self._cfg = ResponseCacheConfig(**(config.config or {}))
        # per-tool list of entries
        self._cache: Dict[str, list[_Entry]] = {}
        # inverted index: tool -> token -> set of entry indices
        self._index: Dict[str, Dict[str, Set[int]]] = defaultdict(lambda: defaultdict(set))

    def _gather_text(self, args: dict[str, Any] | None) -> str:
        """Extract and concatenate text from configured argument fields.

        Args:
            args: Tool arguments dictionary.

        Returns:
            Concatenated text from configured fields.
        """
        if not args:
            return ""
        chunks: list[str] = []
        for f in self._cfg.fields:
            v = args.get(f)
            if isinstance(v, str) and v.strip():
                chunks.append(v)
        return "\n".join(chunks)

    def _find_best(self, tool: str, text: str) -> Tuple[Optional[_Entry], float]:
        """Find the best matching cache entry for the given text.

        Uses inverted index to quickly filter candidates before computing
        cosine similarity. Only entries sharing tokens with the query are
        considered.

        Args:
            tool: Tool name to search cache for.
            text: Query text to match against.

        Returns:
            Tuple of (best matching entry, similarity score).
        """
        bucket = self._cache.get(tool, [])
        if not bucket:
            return None, 0.0

        vec = _vectorize(text)
        query_tokens = set(vec.keys())

        # fast path: use inverted index to find candidate entries
        tool_index = self._index.get(tool, {})
        candidate_indices: Set[int] = set()

        for token in query_tokens:
            if token in tool_index:
                candidate_indices.update(tool_index[token])

        if not candidate_indices:
            return None, 0.0

        best: Optional[_Entry] = None
        best_sim = 0.0
        now = time.time()

        for idx in candidate_indices:
            if idx >= len(bucket):
                continue
            e = bucket[idx]
            if not _is_alive(e, now):
                continue
            sim = _cos_sim(vec, e.vec)
            if sim > best_sim:
                best = e
                best_sim = sim

        return best, best_sim

    def _rebuild_index(self, tool: str) -> None:
        """Rebuild the inverted index for a tool's cache bucket.

        Args:
            tool: Tool name whose index to rebuild.
        """
        self._index[tool].clear()
        for idx, entry in enumerate(self._cache.get(tool, [])):
            for token in entry.tokens:
                self._index[tool][token].add(idx)

    def _evict(self, tool: str) -> None:
        """Evict expired entries and LRU entries beyond max_entries.

        Removes expired entries first, then evicts least-recently-accessed
        entries until the bucket is within max_entries.

        Args:
            tool: Tool name whose bucket to evict from.
        """
        bucket = self._cache.get(tool, [])
        if not bucket:
            return

        now = time.time()
        # remove expired entries
        alive = [e for e in bucket if _is_alive(e, now)]

        # LRU eviction: keep most-recently-accessed entries
        if len(alive) > self._cfg.max_entries:
            alive.sort(key=lambda e: e.last_accessed, reverse=True)
            alive = alive[:self._cfg.max_entries]

        if len(alive) != len(bucket):
            bucket.clear()
            bucket.extend(alive)
            self._rebuild_index(tool)

    async def tool_pre_invoke(self, payload: ToolPreInvokePayload, context: PluginContext) -> ToolPreInvokeResult:
        """Check for cache hit before tool invocation.

        Args:
            payload: Tool invocation payload.
            context: Plugin execution context.

        Returns:
            Result with metadata indicating cache hit status.
        """
        tool = payload.name
        if tool not in self._cfg.cacheable_tools:
            return ToolPreInvokeResult(continue_processing=True)
        text = self._gather_text(payload.args or {})
        if not text:
            return ToolPreInvokeResult(continue_processing=True)
        # keep text for post-invoke storage
        context.set_state("rcbp_last_text", text)
        best, sim = self._find_best(tool, text)
        meta: dict[str, Any] = {"approx_cache": False}
        if best and sim >= self._cfg.threshold:
            # LRU: update access time
            best.last_accessed = time.time()
            meta.update(
                {
                    "approx_cache": True,
                    "similarity": round(sim, 4),
                    "cached_text_len": len(best.text),
                }
            )
            context.metadata["approx_cached_result_available"] = True
            context.metadata["approx_cached_similarity"] = sim
        return ToolPreInvokeResult(metadata=meta)

    async def tool_post_invoke(self, payload: ToolPostInvokePayload, context: PluginContext) -> ToolPostInvokeResult:
        """Store tool result in cache after invocation.

        Args:
            payload: Tool invocation result payload.
            context: Plugin execution context.

        Returns:
            Result with metadata indicating cache storage.
        """
        tool = payload.name
        if tool not in self._cfg.cacheable_tools:
            return ToolPostInvokeResult(continue_processing=True)
        text = context.get_state("rcbp_last_text") if context else ""
        if not text:
            return ToolPostInvokeResult(continue_processing=True)

        now = time.time()
        ttl = max(0, int(self._cfg.ttl))
        expires_at = now + ttl if ttl > 0 else 0.0
        vec = _vectorize(text)
        tokens = set(vec.keys())
        entry = _Entry(
            text=text,
            vec=vec,
            value=payload.result,
            expires_at=expires_at,
            last_accessed=now,
            tokens=tokens,
        )

        bucket = self._cache.setdefault(tool, [])
        entry_idx = len(bucket)
        bucket.append(entry)

        # update inverted index for new entry
        tool_index = self._index[tool]
        for token in tokens:
            tool_index[token].add(entry_idx)

        # evict expired + LRU overflow
        self._evict(tool)

        return ToolPostInvokeResult(metadata={"approx_cache_stored": True})
