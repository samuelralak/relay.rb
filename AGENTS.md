# Agent Guidelines

This file provides guidelines for AI agents working on this codebase.

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

## Code Style

### Ruby/Rails Conventions
- Use `frozen_string_literal: true` at the top of all Ruby files
- Follow Rails naming conventions (snake_case for methods/variables, CamelCase for classes)
- Use spaces inside array brackets: `[ item1, item2 ]`
- Run `bin/rubocop` before committing to ensure style compliance

### Testing
- Run `bin/rails test` to execute the full test suite
- Run `bin/rails test test/models/{model}_test.rb` to test a specific model
- All tests must pass before changes are considered complete

## Project Structure

This is a Ruby on Rails application implementing a Nostr relay. Key directories:

- `app/models/` - ActiveRecord models with concerns
- `app/jobs/` - Background jobs for sync operations
- `app/channels/` - WebSocket channels for Nostr protocol
- `lib/relay_sync/` - Core sync library
- `test/` - Test files mirroring app structure
