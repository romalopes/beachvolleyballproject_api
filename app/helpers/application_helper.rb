module ApplicationHelper
  ICONS = {
    "home" => '<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
    "target" => '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>',
    "dumbbell" => '<path d="m6.5 6.5 11 11"/><path d="m21 21-1-1"/><path d="m3 3 1 1"/><path d="m18 22 4-4"/><path d="m2 6 4-4"/><path d="m3 10 7-7"/><path d="m14 21 7-7"/>',
    "play-circle" => '<circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8"/>',
    "calendar-days" => '<rect width="18" height="18" x="3" y="4" rx="2"/><path d="M16 2v4"/><path d="M8 2v4"/><path d="M3 10h18"/><path d="M8 14h.01"/><path d="M12 14h.01"/><path d="M16 14h.01"/><path d="M8 18h.01"/><path d="M12 18h.01"/><path d="M16 18h.01"/>',
    "clipboard-list" => '<rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="M12 11h4"/><path d="M12 16h4"/><path d="M8 11h.01"/><path d="M8 16h.01"/>',
    "search" => '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    "arrow-left" => '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
    "arrow-right" => '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>',
    "users" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    "map-pin" => '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
    "clock" => '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
    "menu" => '<line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/>',
  }.freeze

  # Renders a lucide-style inline SVG icon.
  def icon(name, size: 24, style: nil, color: nil)
    css = +"vertical-align: middle;"
    css << " #{style}" if style
    css << " color: #{color};" if color
    %(<svg width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="#{css}" aria-hidden="true">#{ICONS.fetch(name)}</svg>).html_safe
  end

  # Tag pill, mirroring the React <Tag /> component.
  def tag_pill(variant: :default, &block)
    classes = "tag"
    classes += " tag-primary" if variant == :primary
    classes += " tag-teal" if variant == :teal
    tag.span(class: classes, &block)
  end

  # "Mon, Jan 5 at 14:30" style short date.
  def short_date(time)
    time.strftime("%a, %b %-d") + " at " + time.strftime("%H:%M")
  end

  # Full date, e.g. "Monday, January 5, 2026 at 14:30".
  def long_date(time)
    time.strftime("%A, %B %-d, %Y") + " at " + time.strftime("%H:%M")
  end
end

