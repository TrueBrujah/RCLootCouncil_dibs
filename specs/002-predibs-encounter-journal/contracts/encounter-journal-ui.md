# Contract: Encounter Journal UI Behavior

## Visibility

- The Dib action is available only for raid contexts.
- Dungeon contexts expose no usable Dib action.
- Known blocked sub-categories are hidden or disabled according to the local matrix.
- Unknown categories are visible by default.

## Submission

- A submission carries stable item identity, current season, player identity, and source context.
- Submission is rejected when the item is invalid, the public workflow is disabled, or the context is not a raid.
- Submission must converge on the shared Pre-Dib request path.

## Safety

- Missing or changing Encounter Journal frames must not raise an addon error.
- UI refresh work must respect combat restrictions.
- The integration must observe Blizzard UI events rather than replace protected functions.
