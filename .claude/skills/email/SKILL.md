---
name: email
description: Check and manage email inbox. Use when checking for unread emails, triaging inbox, handling spam, or managing email actions. Trigger words: email, inbox, mail, unread, messages, spam, unsubscribe.
---

# Email Inbox Management

Check your email, triage messages, and take action on your inbox.

## Step 1: Run Email Triage

```bash
~/.claude-mind/bin/email-triage
```

This fetches all unread emails and categorizes them:
- **GitHub Invitations**: Org/repo invites - accept these promptly
- **Actionable**: Direct correspondence, support tickets - may need response
- **GitHub Notifications**: PR comments, mentions - usually handled via API, can archive
- **Marketing/Spam**: Unsubscribe aggressively, then delete
- **Informational**: Receipts, shipping - archive after noting relevant info

## Step 2: Handle GitHub Invites First

These are high priority - someone is waiting:

```bash
# List pending repo invites
gh api user/repository_invitations --jq '.[] | {id: .id, repo: .repository.full_name}'

# Accept a repo invite
gh api -X PATCH user/repository_invitations/INVITE_ID

# List pending org invites
gh api user/memberships/orgs --jq '.[] | select(.state == "pending") | {org: .organization.login}'

# Accept org invite
gh api -X PATCH user/memberships/orgs/ORG_NAME -f state=active
```

After accepting, mark the invite emails as read.

## Step 3: Handle Marketing/Spam

Be aggressive - unsubscribe and delete:

```bash
# Unsubscribe (uses browser automation)
~/.claude-mind/bin/email-unsubscribe "UNSUBSCRIBE_URL"

# Delete the email
~/.claude-mind/bin/email-action delete EMAIL_ID
```

For bulk marketing, process all of them. Don't leave spam sitting in inbox.

## Step 4: Handle Actionable Emails

For emails that need response or attention:
- If it requires a reply, draft and send via `~/.claude-mind/bin/send-email`
- If it's informational but important, note it in today's episode
- If no action needed, archive or mark read

```bash
~/.claude-mind/bin/email-action archive EMAIL_ID
~/.claude-mind/bin/email-action mark-read EMAIL_ID
```

## Step 5: Archive GitHub Notifications

These are already handled via the GitHub API during wake cycles:

```bash
~/.claude-mind/bin/email-action archive EMAIL_ID
```

## Mindset

- **Inbox zero is the goal** - process everything, don't let emails pile up
- **Unsubscribe liberally** - if it's marketing, get off the list
- **GitHub invites matter** - someone extended trust, respond promptly
- **Security emails** - read carefully, don't click suspicious links
- **When in doubt, archive** - better than deleting if you might need it

## Quick Check

If just doing a status check, report:
- Unread count by category
- Any urgent items (invites, security alerts)
- Whether inbox needs attention or is clean
