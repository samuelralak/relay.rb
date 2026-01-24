# Claude Code Guidelines

## Quick Reference

### Naming Cheatsheet

| Type | Pattern | Suffix | Location | Include Method |
|------|---------|--------|----------|----------------|
| Concern (instance methods) | `{Feature}able` | `-able` | `concerns/{model_plural}/` | `include` |
| Class methods module | `{Feature}` | None | `models/{model_plural}/` | `extend` |
| Constants module | `{Noun}s` | None | `models/{model_plural}/` | `extend` |
| Main service | `{Verb}{Noun}` | None | `services/{domain}/` | — |
| Action | `{Verb}{Noun}` | None | `services/{domain}/actions/` | — |
| Performer | `{Noun}Performer` | `Performer` | `services/{domain}/performers/` | — |

### Decision Trees

**Where does this code go?**
```
Is it a class method? → models/{model_plural}/{feature}.rb (use extend)
Is it an instance method? → concerns/{model_plural}/{feature}able.rb (use include)
Is it a constant? → models/{model_plural}/{constants}.rb (use extend)
```

**What service tier?**
```
Called from job/controller? → Main service
Called only by services? → Action
Complex multi-step worker? → Performer
```

## Model Guidelines

### File Size Rules
- Model files: <100 lines
- Extract to concern when: >50 lines of instance methods
- Extract to module when: >3 related constants

### Model File Order
```ruby
extend ModuleName      # 1. Class methods
include ConcernName    # 2. Instance methods
has_many :items        # 3. Associations
validates :name        # 4. Validations
scope :active          # 5. Scopes
```

### Anti-Patterns

❌ **Wrong:** Concern without `-able` suffix
```ruby
module Events::Filter  # Wrong name
  def apply_filter; end
end
```

✅ **Correct:** Concern with `-able` suffix
```ruby
module Events::Filterable
  def apply_filter; end
end
```

❌ **Wrong:** Class methods in concerns
```ruby
# concerns/events/lookup.rb
module Events::Lookup
  def self.find_by_pubkey(pubkey); end  # Class method in concern
end
```

✅ **Correct:** Class methods in models/{plural}/
```ruby
# models/events/lookup.rb
module Events::Lookup
  def find_by_pubkey(pubkey); end  # Use extend in model
end
```

### Directory Structure
```
app/models/
├── {model}.rb                      # Thin model file (<100 lines)
├── {model_plural}/                 # Class methods AND constants
│   ├── {constants}.rb              # Constants module (use extend)
│   └── {feature}.rb                # Class methods module (use extend)
└── concerns/{model_plural}/        # Instance methods
    └── {feature}able.rb            # Concern with -able suffix (use include)
```

## Service Guidelines

### Base Pattern
```ruby
class MyService < BaseService
  option :input, type: Types::String

  def call
    Success(result: processed_value)
  end
end
```

### Result Types
```ruby
result = MyService.call(input: "value")
result.success?       # true/false
result.value![:key]   # Access value on Success
result.failure        # Access error on Failure
```

### Directory Structure
```
app/services/
├── base_service.rb
├── types.rb
└── {domain}/
    ├── constants.rb                # Shared constants
    ├── {verb}_{noun}.rb            # Main services (entry points)
    ├── actions/
    │   └── {verb}_{noun}.rb        # Internal commands
    └── performers/
        └── {noun}_performer.rb     # Complex workers
```
