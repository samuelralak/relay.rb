# Claude Code Guidelines

## Model Development Guidelines

### Model Organization
1. Keep model files thin (<100 lines)
2. Extract class methods to `models/{resources}/` modules (use `extend`)
3. Extract instance methods to concerns with `-able` naming (use `include`)
4. Use constants modules for related constants
5. Follow this order: extends → includes → associations → validations → scopes

### Module Inclusion
- `extend ModuleName` - adds methods as **class methods**
- `include ModuleName` - adds methods as **instance methods**

### Naming Conventions
- **Concerns (instance methods):** ALWAYS use `-able` suffix
  - `Filterable`, `StatusManageable`, `ProgressTrackable`, `Resumable`
- **Class method modules:** Use logical/standard naming (NOT `-able`)
  - `Finder`, `Lookup`, `Builder`, `Serializer`
- **Constants modules:** Use descriptive nouns
  - `Statuses`, `Kinds`, `TagNames`

### Directory Structure
```
app/models/
├── {model}.rb                      # Thin model file
├── {model_plural}/                 # Constants AND class methods modules
│   ├── {constants}.rb             # e.g., events/kinds.rb, sync_states/statuses.rb
│   └── {class_methods}.rb         # e.g., sync_states/finder.rb (use extend)
├── concerns/
│   └── {model_plural}/            # Model-specific concerns (instance methods)
│       └── {feature}able.rb       # ONLY concerns use -able naming (use include)
└── application_record.rb
```

### When Creating New Models
1. Create the model file in `app/models/`
2. If >3 constants needed, create `app/models/{model_plural}/{constants}.rb`
3. If class methods needed, create `app/models/{model_plural}/{feature}.rb` (use extend)
4. If >50 lines of instance methods, create concerns in `app/models/concerns/{model_plural}/{feature}able.rb`

### Concern Rules (Instance Methods)
- Single responsibility per concern
- ALWAYS use `-able` suffix: `Filterable`, `StatusManageable`, `ProgressTrackable`
- Use `included` block for scopes/callbacks
- No dependencies between concerns

### Class Methods Rules
- Put in `models/{resources}/` directory (NOT concerns)
- Use `extend` to include in model
- Use logical naming (Finder, Builder, etc.) - NOT `-able`

### Reference Examples
- Well-organized model: `app/models/event.rb`
- Constants module: `app/models/events/kinds.rb`
- Concern with scopes: `app/models/concerns/events/filterable.rb`
- Concern with callbacks: `app/models/concerns/events/taggable.rb`
- Class methods module: `app/models/sync_states/finder.rb`
- Status/direction constants: `app/models/sync_states/statuses.rb`

## Service Layer Guidelines

### Service Architecture
Services follow a three-tier hierarchy:
1. **Main Services** - Entry points called from jobs/controllers
2. **Actions** - Internal discrete operations (command pattern)
3. **Performers** - Internal workers for complex multi-step tasks

### Base Service Pattern
All services inherit from `BaseService` which provides:
- `dry-initializer` for typed options
- `dry-monads` Result types (Success/Failure)
- Class-level `call` method

```ruby
class MyService < BaseService
  option :input, type: Types::String

  def call
    # Returns Success(value) or Failure(error)
    Success(result: processed_value)
  end
end
```

### Result Types
Services return `Success` or `Failure` results:
```ruby
result = MyService.call(input: "value")
result.success?       # true/false
result.value![:key]   # Access value on Success
result.failure        # Access error on Failure
```

### Naming Conventions
| Pattern | Use Case | Examples |
|---------|----------|----------|
| `{Verb}{Noun}` | Main services | `ProcessEvent`, `UploadEvents` |
| `{Verb}{Noun}` | Actions | `FetchEvents`, `BuildFilter` |
| `{Noun}Performer` | Performers | (reserved for complex workers) |

### Directory Structure
```
app/services/
├── base_service.rb              # Base class with dry-monads
├── types.rb                     # Type definitions
├── concerns/
│   └── sync/
│       ├── connectionable.rb    # Connection validation
│       ├── timeout_waitable.rb  # Timeout patterns
│       └── error_handleable.rb  # Error handling
└── sync/
    ├── constants.rb             # Shared constants
    │
    │   # Main Services (entry points)
    ├── dispatch_sync_jobs.rb    # Job dispatcher
    ├── process_event.rb         # Event persistence
    ├── sync_with_negentropy.rb  # Negentropy sync
    ├── upload_events.rb         # Event upload
    ├── recover_stale.rb         # Stale/error recovery
    │
    │   # Actions (internal commands)
    ├── actions/
    │   ├── build_filter.rb
    │   ├── build_storage.rb
    │   ├── dispatch_job.rb
    │   ├── fetch_events.rb
    │   ├── normalize_event_data.rb
    │   ├── recover_stale_syncs.rb
    │   └── retry_errored_syncs.rb
    │
    │   # Performers (complex workers)
    └── performers/
        └── process_reconciliation_results.rb
```

### Service Concerns
Use concerns for shared behavior across services:
- `Connectionable` - connection validation and access
- `TimeoutWaitable` - thread-safe wait patterns
- `ErrorHandleable` - error handling and status updates

### When Creating New Services
1. Determine tier: Main service, Action, or Performer
2. Use `dry-initializer` option for typed parameters
3. Return `Success(hash)` or `Failure(error)`
4. Include relevant concerns for shared behavior
5. Extract constants to `sync/constants.rb`

### Reference Examples
- Main service: `app/services/sync/process_event.rb`
- Action: `app/services/sync/actions/fetch_events.rb`
- Performer: `app/services/sync/performers/process_reconciliation_results.rb`
- Concern: `app/services/concerns/sync/connectionable.rb`
