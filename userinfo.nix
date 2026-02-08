{ lib }:
# ============================================================================
# ⚠️  CUSTOMIZE HERE: Replace these values with your own after forking
# ============================================================================
# After test driving this configuration, fork the repository and update
# these values to match your environment, GitHub account, and signing keys.
#
# Configuration options:
# - username: system username
# - fullName: full name for git commits
# - git.github: github username
# - git.signingKey: gpg key id (used by gpg.nix and shells.nix)
# - git.signingFormat: "openpgp" or "ssh" (must be set if signingKey is set)
# - git.email: primary git email address
# - git.emailSecondary: optional secondary email for work/personal separation
#
# Note: If either git.signingKey or git.signingFormat is null, commit
# signing will be disabled.
# ============================================================================
{
  username = "adam";
  fullName = "Adam Williams";
  git = {
    github = "awill1988";
    signingKey = "4A0DB07DEDB705FBA45F557B7A0F7A351FABE619";
    signingFormat = "ssh";
    email = "adam@williams.engineer";
    emailSecondary = "adam@arrofinance.com";
  };
}
