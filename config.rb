activate :autoprefixer
activate :directory_indexes
activate :livereload
activate :sprockets

set :slim, {
  format:     :html,
  pretty:     false,
  sort_attrs: false,
  streaming:  false,
  tabsize:    2,
}

helpers do
  def page_title
    title = ""
    if current_page.data.title
      title << current_page.data.title << ' | '
    end
    title << "Tosainu's Portfolio"
  end
end

configure :development do
  set :debug_assets, true
end

configure :build do
  activate :minify_css
end
