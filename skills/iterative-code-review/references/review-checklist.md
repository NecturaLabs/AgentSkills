# Code Review Checklist

> Sources: Google Engineering Practices, Clean Code (Robert C. Martin), SOLID Principles, Martin Fowler's Refactoring, SonarQube, Airbnb/Google Style Guides

## 1. Design & Architecture

| Rule | Severity | What to Check |
|------|----------|---------------|
| D-1 | Critical | Code well-designed and fits system architecture |
| D-2 | High | Code belongs in this codebase, not a library |
| D-3 | High | Integrates with existing patterns and conventions |
| D-4 | High | No over-engineering — solve today's problem only |
| D-5 | High | Prefer polymorphism over if/else type-checking chains |
| D-6 | High | Use dependency injection, not direct instantiation |
| D-7 | High | Law of Demeter — no `a.getB().getC().doThing()` chains |
| D-8 | Medium | Keep configurable data at high levels |

### SOLID Principles

| Principle | Violation Indicator |
|-----------|-------------------|
| **SRP** | Class handles multiple unrelated responsibilities |
| **OCP** | Adding a type requires modifying existing code |
| **LSP** | Subclass throws NotImplementedException or enforces stricter preconditions |
| **ISP** | Classes implement methods they don't use |
| **DIP** | High-level code directly depends on infrastructure details |

## 2. Complexity

| Metric | Threshold | Action |
|--------|-----------|--------|
| Cyclomatic complexity/function | >10 | Extract methods, use polymorphism |
| Cognitive complexity/function | >15 | Reduce nesting, simplify booleans |
| Function length | >40 lines | Extract smaller methods |
| Class length | >200 lines | Extract classes, apply SRP |
| Parameters | >3-4 | Introduce parameter object |
| Nesting depth | >3 levels | Early returns, extract methods |

## 3. Code Smells

### Bloaters
| Smell | Fix |
|-------|-----|
| Long Method (>40 lines) | Extract Method |
| Large Class | Extract Class/Subclass |
| Primitive Obsession (currency as float) | Value Objects |
| Long Parameter List (>4) | Parameter Object |
| Data Clumps (same vars passed together) | Extract class |

### OO Abusers
| Smell | Fix |
|-------|-----|
| Switch/type-checking statements | Polymorphism |
| Temporary fields | Separate class |
| Refused Bequest (unused inheritance) | Composition |

### Change Preventers
| Smell | Fix |
|-------|-----|
| Divergent Change (one class, many reasons) | Extract Class |
| Shotgun Surgery (one change, many files) | Move Method |

### Dispensables
| Smell | Fix |
|-------|-----|
| Dead code / commented-out code | Delete |
| Speculative Generality | Remove, build when needed |
| Duplicate code | Extract shared method/class |

### Couplers
| Smell | Fix |
|-------|-----|
| Feature Envy | Move method to envied class |
| Inappropriate Intimacy | Encapsulate |
| Message Chains | Hide Delegate |
| Middle Man | Remove |

## 4. Naming

| Rule | Severity |
|------|----------|
| Names descriptive and unambiguous | High |
| No `data1`, `data2` — meaningful distinctions | High |
| Replace magic numbers with named constants | High |
| Consistent vocabulary — one word per concept | High |
| Booleans read as predicates: `isEmpty`, `hasAccess` | Medium |
| Class = noun, Method = verb | Medium |

## 5. Functions

| Rule | Severity |
|------|----------|
| Functions do ONE thing | Critical |
| No side effects | Critical |
| Prefer <3 arguments | High |
| No flag arguments (split into separate methods) | High |
| Command-Query Separation | Medium |
| Extract try/catch into own functions | Medium |

## 6. Error Handling

| Rule | Severity |
|------|----------|
| Never swallow exceptions (empty catch) | Critical |
| Catch specific exceptions, not base types | High |
| Never log AND throw same exception | High |
| Preserve original exception when wrapping | High |
| Error messages descriptive and actionable | High |
| No sensitive info in error messages | Critical |
| Use language cleanup constructs (using/try-with-resources) | Critical |
| Don't return null where empty collection works | High |

## 7. Performance & Resources

| Rule | Severity |
|------|----------|
| Resources properly closed/disposed | Critical |
| No unbounded caches or collections | Critical |
| DB connections returned to pool | Critical |
| No N+1 query patterns | High |
| Appropriate data structures for access pattern | High |
| Event handlers unsubscribed when done | High |

## 8. Concurrency

| Rule | Severity |
|------|----------|
| All shared mutable state protected | Critical |
| No race conditions in check-then-act | Critical |
| Consistent lock ordering (no deadlocks) | Critical |
| Don't call external methods while holding locks | Critical |
| Minimize critical section scope | High |
| Use proper sync, not Thread.sleep() | High |

## 9. Style & Consistency

| Rule | Severity |
|------|----------|
| Follows project's established style | High |
| Style changes NOT mixed with logic changes | High |
| Consistent naming conventions | High |
| Consistent error handling patterns | High |
| Comments explain WHY, not WHAT | High |
| No commented-out code | High |
| Public APIs have doc comments | High |

## 10. API Design

| Rule | Severity |
|------|----------|
| Public API backward compatible | Critical |
| Proper HTTP methods and status codes | High |
| All inputs validated at boundaries | Critical |
| Consistent error response format | High |
| No internal details exposed | High |

## 11. Anti-Patterns to Flag

| Pattern | Severity |
|---------|----------|
| God Class | Critical |
| Spaghetti Code | Critical |
| Premature Optimization | High |
| Copy-Paste Programming | High |
| Golden Hammer (one pattern for everything) | High |
| Lava Flow (dead code nobody removes) | High |
