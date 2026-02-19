#!/usr/bin/env ruby

require "cgi"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
SOURCE_DIR = File.join(ROOT, "blog-posts")
OUTPUT_DIR = File.join(ROOT, "resources")
ARCHIVE_PAGE = File.join(ROOT, "resources.html")
ARCHIVE_INDEX_PAGE = File.join(OUTPUT_DIR, "index.html")

def html_escape(text)
  CGI.escapeHTML(text.to_s)
end

def inline_markdown(text)
  escaped = html_escape(text)
  escaped = escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="\2">\1</a>')
  escaped = escaped.gsub(/`([^`]+)`/, "<code>\\1</code>")
  escaped.gsub(/\*\*([^*]+)\*\*/, "<strong>\\1</strong>")
end

def parse_front_matter(raw)
  lines = raw.lines
  return [{}, raw] unless lines.first&.strip == "---"

  fm_lines = []
  idx = 1
  while idx < lines.length && lines[idx].strip != "---"
    fm_lines << lines[idx]
    idx += 1
  end

  body = lines[(idx + 1)..]&.join.to_s
  meta = {}
  current_key = nil

  fm_lines.each do |line|
    if (m = line.match(/^([a-z_]+):\s*(.*)$/))
      key = m[1]
      value = m[2].strip
      if value.empty?
        meta[key] = []
        current_key = key
      else
        current_key = nil
        cleaned = value.sub(/\A"/, "").sub(/"\z/, "")
        meta[key] = cleaned
      end
      next
    end

    if (m = line.match(/^\s*-\s+(.+)$/)) && current_key && meta[current_key].is_a?(Array)
      cleaned = m[1].strip.sub(/\A"/, "").sub(/"\z/, "")
      meta[current_key] << cleaned
    end
  end

  [meta, body]
end

def render_markdown(markdown)
  html = []
  paragraph_lines = []
  list_mode = nil

  close_list = lambda do
    next unless list_mode

    html << (list_mode == :ul ? "</ul>" : "</ol>")
    list_mode = nil
  end

  flush_paragraph = lambda do
    next if paragraph_lines.empty?

    text = paragraph_lines.join(" ")
    html << "<p>#{inline_markdown(text)}</p>"
    paragraph_lines = []
  end

  markdown.each_line do |raw_line|
    line = raw_line.rstrip
    stripped = line.strip

    if stripped.empty?
      flush_paragraph.call
      close_list.call
      next
    end

    if (m = line.match(/^###\s+(.+)$/))
      flush_paragraph.call
      close_list.call
      html << "<h3>#{inline_markdown(m[1])}</h3>"
      next
    end

    if (m = line.match(/^##\s+(.+)$/))
      flush_paragraph.call
      close_list.call
      html << "<h2>#{inline_markdown(m[1])}</h2>"
      next
    end

    if (m = line.match(/^#\s+(.+)$/))
      flush_paragraph.call
      close_list.call
      html << "<h1>#{inline_markdown(m[1])}</h1>"
      next
    end

    if (m = line.match(/^\d+\.\s+(.+)$/))
      flush_paragraph.call
      if list_mode != :ol
        close_list.call
        html << "<ol>"
        list_mode = :ol
      end
      html << "<li>#{inline_markdown(m[1])}</li>"
      next
    end

    if (m = line.match(/^-+\s+(.+)$/))
      flush_paragraph.call
      if list_mode != :ul
        close_list.call
        html << "<ul>"
        list_mode = :ul
      end
      html << "<li>#{inline_markdown(m[1])}</li>"
      next
    end

    if (m = line.match(/^>\s*(.+)$/))
      flush_paragraph.call
      close_list.call
      html << "<blockquote><p>#{inline_markdown(m[1])}</p></blockquote>"
      next
    end

    close_list.call if list_mode
    paragraph_lines << stripped
  end

  flush_paragraph.call
  close_list.call
  html.join("\n")
end

def strip_duplicate_title_heading(body, title)
  lines = body.lines
  idx = 0
  idx += 1 while idx < lines.length && lines[idx].strip.empty?

  return body unless idx < lines.length && lines[idx].strip == "# #{title}"

  lines.delete_at(idx)
  lines.delete_at(idx) while idx < lines.length && lines[idx].strip.empty?
  lines.join
end

def nav_html
  <<~HTML
    <header class="topbar">
      <a class="brand" href="/index.html#top" aria-label="Sermon Notes Home">
        <img src="/assets/sermon-notes-logo-mark.svg" alt="Sermon Notes logo">
      </a>
      <nav aria-label="Main navigation">
        <a class="nav-link" href="/index.html#features">Features</a>
        <a class="nav-link" href="/index.html#faq">FAQ</a>
        <a class="nav-link" href="/index.html#pricing">Pricing</a>
      </nav>
      <a class="cta-btn cta-btn-nav" href="mailto:hello@sermonnotes.app?subject=Early%20Access%20-%20Sermon%20Notes">Join Early Access</a>
    </header>
  HTML
end

def reveal_script
  <<~HTML
    <script>
      const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("on");
            observer.unobserve(entry.target);
          }
        });
      }, { threshold: 0.12 });

      document.querySelectorAll(".reveal").forEach((el) => observer.observe(el));
    </script>
  HTML
end

def post_template(post, article_html, prev_post, next_post)
  keyword_tags = post[:keywords].first(3).map { |keyword| "<span class=\"tag\">#{html_escape(keyword)}</span>" }.join
  prev_link = prev_post ? "<a class=\"btn-soft\" href=\"/resources/#{html_escape(prev_post[:slug])}.html\">&larr; #{html_escape(prev_post[:title])}</a>" : "<span></span>"
  next_link = next_post ? "<a class=\"btn-soft\" href=\"/resources/#{html_escape(next_post[:slug])}.html\">#{html_escape(next_post[:title])} &rarr;</a>" : "<span></span>"

  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta name="description" content="#{html_escape(post[:description])}">
      <title>#{html_escape(post[:title])} | Sermon Notes Resources</title>
      <link rel="icon" href="/favicon.ico" sizes="any">
      <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
      <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
      <link rel="icon" type="image/svg+xml" href="/assets/sermon-notes-icon.svg">
      <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
      <link rel="manifest" href="/site.webmanifest">
      <link rel="stylesheet" href="/resources.css">
    </head>
    <body>
      <div class="nav-grid-overlay" aria-hidden="true"></div>
      <div class="site">
        #{nav_html}
        <main id="top">
          <section class="post-layout reveal">
            <article class="article-wrap">
              <p class="post-meta">Resource Article</p>
              <h1 class="post-title">#{html_escape(post[:title])}</h1>
              <p class="post-dek">#{html_escape(post[:description])}</p>
              <div class="tag-row">#{keyword_tags}</div>
              <section class="prose">
                #{article_html}
              </section>
              <div class="post-nav">
                <a class="btn-soft" href="/resources.html">&larr; Back to Resources</a>
                <div>
                  #{prev_link}
                  #{next_link}
                </div>
              </div>
            </article>
            <aside class="sidebar">
              <section class="card">
                <h3>Browse Topics</h3>
                <ul class="link-list">
                  <li><a href="/resources.html#sermon-notes">Sermon Notes</a></li>
                  <li><a href="/resources.html#bible-study">Bible Study Workflow</a></li>
                  <li><a href="/resources.html#retention">Retention and Review</a></li>
                </ul>
              </section>
              <section class="card">
                <h3>Next Step</h3>
                <p>Want early access to the app? Join the list and get updates as new features ship.</p>
                <p style="margin-top: 0.85rem;">
                  <a class="cta-btn" href="mailto:hello@sermonnotes.app?subject=Early%20Access%20-%20Sermon%20Notes">Join Early Access</a>
                </p>
              </section>
            </aside>
          </section>
        </main>
        <footer>&copy; #{Time.now.year} Sermon Notes</footer>
      </div>
      #{reveal_script}
    </body>
    </html>
  HTML
end

def archive_template(posts)
  cards = posts.each_with_index.map do |post, idx|
    card_id =
      case idx
      when 0 then "sermon-notes"
      when 5 then "bible-study"
      when 10 then "retention"
      else nil
      end

    tags = post[:keywords].first(3).map { |kw| "<span class=\"tag\">#{html_escape(kw)}</span>" }.join
    <<~CARD
      <article class="card archive-card reveal"#{card_id ? " id=\"#{card_id}\"" : ""}>
        <p class="post-meta">Resource ##{idx + 1}</p>
        <h2><a href="/resources/#{html_escape(post[:slug])}.html">#{html_escape(post[:title])}</a></h2>
        <p>#{html_escape(post[:description])}</p>
        <div class="tag-row">#{tags}</div>
        <p><a class="btn-soft" href="/resources/#{html_escape(post[:slug])}.html">Read Article</a></p>
      </article>
    CARD
  end.join("\n")

  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta name="description" content="Sermon Notes resources: practical guides for sermon note-taking, Bible study workflow, and long-term retention.">
      <title>Resources | Sermon Notes</title>
      <link rel="icon" href="/favicon.ico" sizes="any">
      <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
      <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
      <link rel="icon" type="image/svg+xml" href="/assets/sermon-notes-icon.svg">
      <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
      <link rel="manifest" href="/site.webmanifest">
      <link rel="stylesheet" href="/resources.css">
    </head>
    <body>
      <div class="nav-grid-overlay" aria-hidden="true"></div>
      <div class="site">
        #{nav_html}
        <main id="top">
          <section class="hero reveal">
            <h1>
              <span class="hero-chunk">Practical <span class="hl" style="--hl-delay: 330ms;">Resources</span></span>
              <span class="hero-chunk">for better sermon and</span>
              <span class="hero-chunk">Bible study notes.</span>
            </h1>
            <p>These articles are written to help readers capture, organize, and apply Scripture with consistency. Browse by topic and use what fits your workflow.</p>
          </section>
          <section class="archive-grid">
            #{cards}
          </section>
        </main>
        <footer>&copy; #{Time.now.year} Sermon Notes</footer>
      </div>
      #{reveal_script}
    </body>
    </html>
  HTML
end

FileUtils.mkdir_p(OUTPUT_DIR)
posts = []

Dir.glob(File.join(SOURCE_DIR, "*.md")).sort.each do |file_path|
  next if File.basename(file_path) == "INDEX.md"

  raw = File.read(file_path)
  meta, body = parse_front_matter(raw)
  slug = meta["slug"] || File.basename(file_path, ".md")
  title = meta["title"] || slug.tr("-", " ").split.map(&:capitalize).join(" ")
  description = meta["description"] || ""
  keywords = meta["keywords"].is_a?(Array) ? meta["keywords"] : []
  cleaned_body = strip_duplicate_title_heading(body, title)

  posts << {
    file_path: file_path,
    slug: slug,
    title: title,
    description: description,
    keywords: keywords,
    article_html: render_markdown(cleaned_body)
  }
end

posts.each_with_index do |post, idx|
  prev_post = idx.positive? ? posts[idx - 1] : nil
  next_post = idx < (posts.length - 1) ? posts[idx + 1] : nil
  html = post_template(post, post[:article_html], prev_post, next_post)
  File.write(File.join(OUTPUT_DIR, "#{post[:slug]}.html"), html)
end

archive_html = archive_template(posts)
File.write(ARCHIVE_PAGE, archive_html)
File.write(ARCHIVE_INDEX_PAGE, archive_html)

puts "Generated #{posts.length} blog post pages, #{ARCHIVE_PAGE}, and #{ARCHIVE_INDEX_PAGE}."
