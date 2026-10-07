# Phase 1: Organisation Tree View (Like Regions.tsx)

## Objective
Replace the flat list with CSS indentation in `Organisations.tsx` with a proper recursive tree component inspired by Wine Words `Regions.tsx`.

## Scope
- Create reusable `OrganisationTreeNode` component
- Refactor `Organisations.tsx` to use recursive tree rendering
- Add Expand All / Collapse All functionality
- Fix "Show archived" to be inclusive (active + archived)
- Preserve expansion state for back-navigation
- Search with ancestor path expansion

## Files to Create
- `src/components/OrganisationTreeNode.tsx` - Recursive tree node component

## Files to Modify
- `src/pages/Organisations.tsx` - Tree refactor

## Acceptance Criteria
- [ ] Tree renders with proper nested `<ul>/<li>` structure
- [ ] Separate expand/collapse button from name link (keyboard accessible)
- [ ] Clicking name navigates to `/organisations/:id`
- [ ] Expand All / Collapse All buttons work
- [ ] Search filters with ancestor path expansion
- [ ] "Show archived" includes archived records (not exclusive)
- [ ] Expansion state preserved on back-navigation
- [ ] Cycle detection (visited-ID protection)
- [ ] Logo/acronym, type badge, status, child count displayed
- [ ] Highlighted search results

## Technical Details

### OrganisationTreeNode Component
```tsx
interface OrganisationTreeNodeProps {
  organisation: Organisation;
  depth: number;
  childCount: number;
  collapsedIds: Set<number>;
  onToggle: (id: number) => void;
  searchTerm?: string;
  highlightedIds?: Set<number>;
}
```

Features:
- Recursive rendering for children
- ChevronRight icon for expand/collapse (rotated via CSS)
- Keyboard accessible (Enter/Space on button)
- Logo/acronym fallback
- Type badge (organisation_type)
- Status badge (active/archived)
- Child count badge
- Highlighted state for search matches

### Organisations.tsx Changes
- Build nested tree from flat API response using `parent_organisation_id` and `depth`
- Use `Set<number>` for collapsed IDs state
- Search: filter organisations, compute highlighted IDs + ancestor paths
- Expand All / Collapse All: operate on all IDs in current filtered set
- Persist collapsedIds in localStorage keyed by view state
- Fix showArchived: when false, filter to active only; when true, show all (active + archived)

## API Usage
- Continue using `GET /api/v1/organisations?tree=1`
- Response includes: `parent_organisation_id`, `depth`, `child_count`, `logo_url`, `logo_attached`, `acronym`, `organisation_type`, `status`, `status_label`

## Dependencies
- lucide-react: ChevronRight, Building2, Archive
- react-router-dom: Link
- ../api: api, Organisation type