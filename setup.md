# Pre-Bootstrap Setup (do these manually)

1. Complete macOS setup with dedicated Apple ID
2. Open **System Settings → Privacy & Security → Full Disk Access** → add Terminal.app
3. Open **Messages.app**, sign in, send a test message to yourself
4. Run `xcode-select --install` in Terminal
5. Install Claude Code: `npm install -g @anthropic-ai/claude-code` (install Node first if needed)
6. Authenticate Claude Code: `claude` and follow prompts
7. Clone this repo: `git clone https://github.com/[YOU]/samara.git ~/samara`
8. Fill in the bracketed values in `samara.md`
9. Run: `claude -p "$(cat ~/samara/samara.md)"`
10. Approve permission dialogs as they appear
