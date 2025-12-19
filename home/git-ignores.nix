{
  programs.git.ignores = [
    # editor swap/session files
    "[._]*.s[a-v][a-z]"
    "[._]*.sw[a-p]"
    "[._]s[a-rt-v][a-z]"
    "[._]ss[a-gi-z]"
    "Session.vim"
    "Sessionx.vim"
    ".netrwhist"
    "[._]*.un~"

    # generic temp files
    "*~"
    "*.bak"
    "*.tmp"
    "*.temp"
    ".#*"
    "#*#"
    "*.dmp"
    "*.stackdump"
    "*.pcap"
    "*.pcapng"

    # tags
    "tags"

    # macos
    ".DS_Store"
    ".AppleDouble"
    ".LSOverride"
    "Icon"
    "Icon\r"
    "._*"
    ".DocumentRevisions-V100"
    ".fseventsd"
    ".Spotlight-V100"
    ".TemporaryItems"
    ".Trashes"
    ".VolumeIcon.icns"
    ".com.apple.timemachine.donotpresent"
    ".AppleDB"
    ".AppleDesktop"
    "Network Trash Folder"
    "Temporary Items"
    ".apdisk"
    "__MACOSX/"
    ".localized"

    # linux
    ".Trash-*"
    ".fuse_hidden*"
    ".nfs*"
    "lost+found"
    ".directory"

    # windows
    "Thumbs.db"
    "ehthumbs.db"
    "ehthumbs_vista.db"
    "Desktop.ini"
    "IconCache.db"
    "$RECYCLE.BIN/"
    "System Volume Information/"
    "*.lnk"
    "*.url"

    # ios/xcode
    "DerivedData/"
    "build/"
    "*.xcuserstate"
    "*.xccheckout"
    "*.xcscmblueprint"
    "*.moved-aside"
    "*.pbxuser"
    "*.mode1v3"
    "*.mode2v3"
    "*.perspectivev3"
    "xcuserdata/"
    "*.ipa"
    "*.dSYM"
    "*.dSYM.zip"

    # swift/swiftpm/cocoapods/carthage
    ".build/"
    ".swiftpm/"
    "Packages/"
    "Pods/"
    "Carthage/Build/"
    "*.xcframework"
    "*.swiftmodule"

    # direnv
    ".direnv/"

    # ai tools
    ".claude/"
    ".claude.json"
    ".claude.settings.json"
    ".gemini/"
    ".gemini.json"
    ".codex/"
    ".codex.json"
    ".aider*"
    ".cursor/"
    ".windsurf/"

    # media
    "*.mp4"
  ];
}
