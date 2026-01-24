---
name: recall
description: Semantic memory recall using FTS5 and Chroma. Use PROACTIVELY whenever the user asks about past events, themes, conversations, or when historical context would enrich a response. Trigger words: remember, when did we, what did we talk about, last time, before, previously, that conversation, that time, history, past, recall.
context: fork
allowed-tools:
  - Bash
  - Read
---

# Semantic Memory Recall

This skill searches through semantic memory indexes for associative recall of past conversations, themes, and context.

## When to Use This Skill

**Use proactively** when:
- User asks about past conversations or events
- User references "that time when..." or "remember when..."
- Historical context would enrich your response
- User asks about themes discussed previously
- You need to recall what was said about a topic

## Two Memory Systems

### 1. SQLite FTS5 (Keyword Search)
Fast keyword matching with BM25 ranking.

```bash
~/.claude-mind/system/bin/memory-index search "query" [limit]
```

Best for: Specific terms, names, dates, exact phrases

### 2. Chroma Vector Database (Semantic Search)
Embedding-based similarity search - finds related content even with different wording.

```bash
~/.claude-mind/system/bin/chroma-query "query" [n_results]
```

Best for: Themes, concepts, "conversations like X", finding related discussions

## Search Strategy

1. **Determine query type**:
   - Specific term/name/date → Use FTS5 first
   - Theme/concept/vague reference → Use Chroma first
   - Comprehensive search → Use both

2. **Run searches**:
```bash
# Keyword search (FTS5)
~/.claude-mind/system/bin/memory-index search "coffee shops" 10

# Semantic search (Chroma)
~/.claude-mind/system/bin/chroma-query "conversations about morning routines" 5

# For comprehensive recall, run both
~/.claude-mind/system/bin/memory-index search "project planning" 5
~/.claude-mind/system/bin/chroma-query "discussions about work priorities and goals" 5
```

3. **Synthesize results**: Combine findings from both systems, noting dates and context.

## Output Format

When presenting recalled memories:
- Lead with the most relevant finding
- Include dates to establish timeline
- Quote key excerpts when helpful
- Note which system found each result (keyword vs semantic match)
- Connect findings to the user's current question

## Examples

**User:** "What did we talk about when I was at that coffee shop?"

```bash
# Semantic search for coffee shop conversations
~/.claude-mind/system/bin/chroma-query "coffee shop conversation" 5

# Keyword backup
~/.claude-mind/system/bin/memory-index search "coffee" 5
```

**User:** "Remember that discussion about Q1 planning?"

```bash
# Semantic for the theme
~/.claude-mind/system/bin/chroma-query "Q1 planning discussion goals priorities" 5

# Keyword for specifics
~/.claude-mind/system/bin/memory-index search "Q1" 5
```

**User:** "What have I said about my work situation?"

```bash
# Broad semantic search
~/.claude-mind/system/bin/chroma-query "work job career situation feelings" 10

# Follow up with specific terms found
~/.claude-mind/system/bin/memory-index search "specific_term_found" 5
```

## Data Sources

Both systems index:
- Episode logs (daily conversation records)
- Reflections (dream cycle outputs)
- Learnings
- Observations
- Decisions
- Person profiles

Results include source type and date for context.
