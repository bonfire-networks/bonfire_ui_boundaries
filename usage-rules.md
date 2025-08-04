# Bonfire.UI.Boundaries Usage Rules

Bonfire.UI.Boundaries provides UI components for managing permissions, access control, and privacy boundaries in the Bonfire ecosystem. It offers interfaces for circles, blocks, ACLs, and role management.

## Core Concepts

### Boundaries UI
The visual interface layer for Bonfire's boundary system, allowing users to:
- Set privacy and access controls on content
- Manage circles (groups of users)
- Block or silence users
- Create and manage Access Control Lists (ACLs)
- Define and assign roles with specific permissions

### Component Types
- **Stateless Components**: Use `Bonfire.UI.Common.Web, :stateless_component` for UI without internal state
- **Stateful Components**: Use `Bonfire.UI.Common.Web, :stateful_component` for components managing their own state
- **Live Handlers**: Centralized event handling for boundary-related actions

### Key Components
- `SetBoundariesLive`: Main interface for setting boundaries on content
- `MyCirclesLive`: Manage user's circles
- `BlockButtonLive`: Interface for blocking/silencing users
- `IfCan`: Conditional rendering based on permissions
- `RolesDropdownLive`: Select roles for circle members

## Core Module Setup

```elixir
defmodule MyApp.BoundaryComponent do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils
  
  # Define props
  prop object, :any
  prop boundary_preset, :string, default: "public"
  prop to_circles, :list, default: []
end
```

## Basic Usage

### Setting Boundaries on Content

```elixir
# In a Surface template (.sface)
<Bonfire.UI.Boundaries.SetBoundariesLive
  to_boundaries={@to_boundaries}
  to_circles={@to_circles}
  exclude_circles={@exclude_circles}
  my_circles={@my_circles}
  __context__={@__context__}
/>
```

### Checking Permissions with IfCan

```elixir
# Conditionally render based on permissions
<Bonfire.UI.Boundaries.IfCan 
  object={@post} 
  verbs={[:edit, :delete]}
>
  <button>Edit Post</button>
  <:if_not>
    <span>You cannot edit this post</span>
  </:if_not>
</Bonfire.UI.Boundaries.IfCan>
```

### Block/Silence Button

```elixir
<Bonfire.UI.Boundaries.BlockButtonLive
  object={@user}
  type={:block}
  scope={:instance}
  parent_id="block_modal"
  with_icon
  class="btn btn-ghost"
/>
```

## API Patterns

### Boundary Presets
The system supports several built-in boundary presets:

```elixir
@presets ["public", "local", "mentions", "custom"]

# Get current preset from boundaries
preset = Bonfire.UI.Boundaries.SetBoundariesLive.boundaries_to_preset(to_boundaries)

# Clean boundaries when switching presets
clean_boundaries = Bonfire.UI.Boundaries.SetBoundariesLive.set_clean_boundaries(
  to_boundaries,
  "public",
  "Public"
)
```

### Circle Management

```elixir
# List user's circles
circles = Bonfire.UI.Boundaries.SetBoundariesLive.list_my_circles(current_user)

# List circles with global options
circles_with_global = Bonfire.UI.Boundaries.SetBoundariesLive.list_my_circles_with_global(scope)

# Format circles for multiselect
options = Bonfire.UI.Boundaries.SetBoundariesLive.circles_for_multiselect(context)
```

### Live Select Integration

```elixir
# Handle live select changes for circle/user selection
def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
  Bonfire.UI.Boundaries.SetBoundariesLive.live_select_change(
    live_select_id, 
    search, 
    :to_circles, 
    socket
  )
end
```

## Advanced Patterns

### Custom Boundary Selection

```elixir
# In LiveHandler
def handle_event("select_boundary", %{"id" => acl_id} = params, socket) do
  to_boundaries = Bonfire.UI.Boundaries.SetBoundariesLive.set_clean_boundaries(
    e(assigns(socket), :to_boundaries, []),
    acl_id,
    e(params, "name", acl_id)
  )
  
  {:noreply, assign(socket, :to_boundaries, to_boundaries)}
end
```

### Multi-Select for Circles and Users

```elixir
def handle_event("multi_select", %{data: data, text: _text}, socket) do
  field = maybe_to_atom(e(data, "field", :to_boundaries))
  
  circle_data = case data do
    %{"id" => id, "name" => name} ->
      %{id: id, name: name, field: field}
    other ->
      other
  end
  
  current_values = e(assigns(socket), field, [])
  
  # Check for duplicates
  unless Enum.any?(current_values, fn {existing, _} -> 
    id(existing) == id(circle_data) 
  end) do
    updated_list = current_values ++ [{circle_data, nil}]
    
    {:noreply, assign(socket, field, updated_list)}
  end
end
```

### Boundary Preview

```elixir
# Preview boundaries for a specific user
def preview(socket, user_id, username) do
  current_user = current_user(socket)
  boundaries = socket.assigns[:to_boundaries] || []
  
  opts = [
    preview_for_id: user_id,
    boundary: "mentions",
    to_circles: e(assigns(socket), :to_circles, [])
  ]
  
  with {:ok, verbs} <- Bonfire.Boundaries.Acls.preview(current_user, opts) do
    role = Bonfire.Boundaries.Roles.preset_boundary_role_from_acl(verbs)
    
    socket
    |> assign(
      preview_boundary_for_username: username,
      preview_boundary_for_id: user_id,
      preview_boundary_verbs: verbs
    )
  end
end
```

## Event Handling

### Block/Unblock Events

```elixir
# Block a user
def handle_event("block", %{"id" => user_id, "block_type" => type, "scope" => scope}, socket) do
  can_instance_wide = Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance)
  
  with {:ok, status} <- 
    if can_instance_wide do
      Bonfire.Boundaries.Blocks.block(user_id, maybe_to_atom(type), maybe_to_atom(scope))
    else
      Bonfire.Boundaries.Blocks.block(user_id, maybe_to_atom(type), socket)
    end do
    
    {:noreply, assign_flash(socket, :info, status)}
  end
end
```

### ACL Management

```elixir
# Create new ACL
def handle_event("acl_create", %{"name" => name} = attrs, socket) do
  current_user = current_user_required!(socket)
  
  with {:ok, %{id: id} = acl} <- 
    Bonfire.Boundaries.Acls.create(attrs, current_user: current_user) do
    
    {:noreply,
     socket
     |> assign(acls: [acl] ++ e(assigns(socket), :acls, []))
     |> assign_flash(:info, l("Boundary created!"))
     |> redirect_to(~p"/boundaries/acl/#{id}")}
  end
end
```

## Component Communication

### Update Other Components

```elixir
# Send updates to CustomizeBoundaryLive component
maybe_send_update(
  Bonfire.UI.Boundaries.CustomizeBoundaryLive,
  "customize_boundary_live",
  %{
    to_boundaries: updated_boundaries,
    to_circles: updated_circles
  }
)
```

### Async Boundary Checking

```elixir
# Check boundaries for multiple components efficiently
def update_many(assigns_sockets, opts \\ []) do
  update_many_async(
    assigns_sockets,
    [
      skip_if_set: :object_boundary,
      preload_status_key: :preloaded_async_boundaries,
      assigns_to_params_fn: &assigns_to_params/1,
      preload_fn: &do_preload_many/3
    ]
  )
end
```

## Best Practices

### Always Use Context
Pass `__context__` to components for proper user context:

```elixir
# ✅ Good
<Bonfire.UI.Boundaries.SetBoundariesLive __context__={@__context__} />

# ❌ Bad
<Bonfire.UI.Boundaries.SetBoundariesLive />
```

### Preload Circles Once
Avoid reloading circles on every render:

```elixir
# ✅ Good - Load once in mount/update
def update(assigns, socket) do
  {:ok,
   socket
   |> assign(assigns)
   |> assign_new(:my_circles, fn ->
     Bonfire.Boundaries.Circles.list_my(current_user(assigns))
   end)}
end

# ❌ Bad - Loading in render
def render(assigns) do
  assigns
  |> assign(:my_circles, list_my_circles(current_user(assigns)))
  |> render_sface()
end
```

### Handle Permissions Properly
Check permissions before showing sensitive UI:

```elixir
# ✅ Good
assign(
  :can_instance_wide?,
  Bonfire.Boundaries.can?(assigns[:__context__], :block, :instance_wide)
)

# ❌ Bad - Assuming permissions
<button :if={true}>Block Instance-wide</button>
```

## Integration with Other Extensions

### With Smart Input (Composer)

```elixir
# In smart_input component
<Bonfire.UI.Boundaries.SetBoundariesLive
  to_boundaries={@to_boundaries}
  to_circles={@to_circles}
  create_object_type={@create_object_type}
  open_boundaries={@open_boundaries}
/>
```

### With Feeds

```elixir
# Show boundary info on activities
<Bonfire.UI.Boundaries.BoundaryIconLive 
  object_boundary={@activity_boundary} 
/>
```

### With Profile Pages

```elixir
# Show if user is blocked
<Bonfire.UI.Boundaries.ProfileBlockedIndicatorLive
  user={@user}
  __context__={@__context__}
/>
```

## Anti-Patterns to Avoid

### ❌ Direct Boundary Manipulation
```elixir
# Bad - Bypassing the boundary system
socket |> assign(:to_boundaries, [{"public", "Public"}])

# Good - Use provided functions
boundaries = Bonfire.UI.Boundaries.SetBoundariesLive.set_clean_boundaries(
  current_boundaries, "public", "Public"
)
```

### ❌ Forgetting Scope Context
```elixir
# Bad - Not considering instance vs user scope
Bonfire.Boundaries.Blocks.block(user_id, :silence, nil)

# Good - Properly handle scope
scope = if can_instance_wide, do: :instance_wide, else: socket
Bonfire.Boundaries.Blocks.block(user_id, :silence, scope)
```

### ❌ Not Handling Duplicates
```elixir
# Bad - Adding duplicates to circles
updated = current_circles ++ [new_circle]

# Good - Check for existing entries
unless Enum.any?(current_circles, fn {existing, _} -> 
  id(existing) == id(new_circle) 
end) do
  current_circles ++ [{new_circle, nil}]
end
```

## Performance Considerations

- Use `update_many_async` for batch boundary checks
- Preload circles and ACLs in mount/update, not render
- Cache boundary calculations when possible
- Use `:skip_if_set` option to avoid rechecking boundaries

## Debugging

### Check Current Boundaries
```elixir
# In LiveView socket
dbg(assigns(socket)[:to_boundaries])
dbg(assigns(socket)[:to_circles])
dbg(assigns(socket)[:boundary_preset])
```

### Trace Boundary Events
```elixir
# Add to handle_event
def handle_event(event, params, socket) do
  debug(event, "boundary event")
  debug(params, "params")
  # ... rest of handler
end
```

### Verify Permissions
```elixir
# Check what current user can do
Bonfire.Boundaries.can?(socket.assigns.__context__, :read, object) |> debug("can read?")
Bonfire.Boundaries.can?(socket.assigns.__context__, :edit, object) |> debug("can edit?")
```