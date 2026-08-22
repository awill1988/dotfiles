# -*- coding: utf-8 -*-
"""Location: ./plugins/cached_tool_result/cached_tool_result.py
Copyright 2025
SPDX-License-Identifier: Apache-2.0
Authors: Mihai Criveti

Cached Tool Result Plugin.
Stores idempotent tool results in an in-memory LRU cache keyed by tool name
and selected argument fields. Reads are advisory (metadata) due to framework
constraints; writes occur in tool_post_invoke.

Eviction: LRU (least recently used) when max_entries is reached. TTL is
optional — set to 0 to disable time-based expiration entirely.
"""

# Future
from __future__ import annotations

# Standard
from collections import OrderedDict
from dataclasses import dataclass
import hashlib
import time
from typing import Any, Dict, List, Optional

# Third-Party
import orjson
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


class CacheConfig(BaseModel):
    """Configuration for cached tool result plugin.

    Attributes:
        cacheable_tools: List of tool names that should be cached.
        ttl: Time-to-live in seconds (0 = no expiry, rely on LRU eviction).
        max_entries: Maximum cache entries before LRU eviction kicks in.
        key_fields: Optional mapping of tool names to specific argument fields to use for cache keys.
    """

    cacheable_tools: List[str] = Field(default_factory=list)
    ttl: int = 0
    max_entries: int = 5000
    key_fields: Optional[Dict[str, List[str]]] = None  # {tool: [fields...]}


@dataclass
class _Entry:
    """Cache entry containing a value and optional expiration timestamp.

    Attributes:
        value: Cached tool result.
        expires_at: Unix timestamp when entry expires (0.0 = never).
    """

    value: Any
    expires_at: float


# LRU cache: OrderedDict preserves insertion order, move_to_end on access
_CACHE: OrderedDict[str, _Entry] = OrderedDict()


def _make_key(tool: str, args: dict | None, fields: Optional[List[str]]) -> str:
    """Generate a cache key hash from tool name and selected argument fields.

    Args:
        tool: Tool name.
        args: Tool arguments dictionary.
        fields: Optional list of specific argument fields to include in the key.

    Returns:
        SHA256 hex digest cache key.
    """
    base = {"tool": tool, "args": {}}
    if args:
        if fields:
            base["args"] = {k: args.get(k) for k in fields}
        else:
            base["args"] = args
    raw = orjson.dumps(base, default=str, option=orjson.OPT_SORT_KEYS)
    return hashlib.sha256(raw).hexdigest()


def _is_alive(entry: _Entry, now: float) -> bool:
    """Check whether a cache entry is still valid.

    Args:
        entry: Cache entry to check.
        now: Current unix timestamp.

    Returns:
        True if entry has no expiry or hasn't expired yet.
    """
    return entry.expires_at == 0.0 or entry.expires_at > now


class CachedToolResultPlugin(Plugin):
    """Cache idempotent tool results (write-through, LRU eviction)."""

    def __init__(self, config: PluginConfig) -> None:
        """Initialize the cached tool result plugin.

        Args:
            config: Plugin configuration.
        """
        super().__init__(config)
        self._cfg = CacheConfig(**(config.config or {}))

    async def tool_pre_invoke(self, payload: ToolPreInvokePayload, context: PluginContext) -> ToolPreInvokeResult:
        """Check cache before tool invocation and store cache key in context.

        Args:
            payload: Tool invocation payload.
            context: Plugin execution context.

        Returns:
            Result with cache hit/miss metadata.
        """
        tool = payload.name
        if tool not in self._cfg.cacheable_tools:
            return ToolPreInvokeResult(continue_processing=True)
        fields = (self._cfg.key_fields or {}).get(tool)
        key = _make_key(tool, payload.args or {}, fields)
        # persist key for post-invoke
        context.set_state("cache_key", key)
        context.set_state("cache_tool", tool)
        ent = _CACHE.get(key)
        now = time.time()
        if ent and _is_alive(ent, now):
            # LRU: promote to most-recently-used
            _CACHE.move_to_end(key)
            return ToolPreInvokeResult(metadata={"cache_hit": True, "key": key})
        elif ent:
            # expired — remove stale entry
            del _CACHE[key]
        return ToolPreInvokeResult(metadata={"cache_hit": False, "key": key})

    async def tool_post_invoke(self, payload: ToolPostInvokePayload, context: PluginContext) -> ToolPostInvokeResult:
        """Store tool result in cache after invocation.

        Args:
            payload: Tool invocation result payload.
            context: Plugin execution context.

        Returns:
            Result with cache storage metadata.
        """
        tool = payload.name
        if tool not in self._cfg.cacheable_tools:
            return ToolPostInvokeResult(continue_processing=True)
        key = context.get_state("cache_key") if context else None
        if not key:
            key = _make_key(tool, None, None)
        ttl = max(0, int(self._cfg.ttl))
        expires_at = time.time() + ttl if ttl > 0 else 0.0
        _CACHE[key] = _Entry(value=payload.result, expires_at=expires_at)
        # promote to most-recently-used
        _CACHE.move_to_end(key)
        # LRU eviction: pop oldest entries until within limit
        while len(_CACHE) > self._cfg.max_entries:
            _CACHE.popitem(last=False)
        return ToolPostInvokeResult(metadata={"cache_stored": True, "key": key, "ttl": ttl})
