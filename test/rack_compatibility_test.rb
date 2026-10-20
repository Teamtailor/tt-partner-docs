# Run from the repository root: bundle exec ruby test/rack_compatibility_test.rb
require 'bundler/setup'
require 'minitest/autorun'
require 'middleman-core'
require 'middleman-core/load_paths'
Middleman.setup_load_paths
require 'middleman-core/rack'

class RackCompatibilityTest < Minitest::Test
  def self.request
    @request ||= begin
      app = Middleman::Application.new do
        config[:mode] = :build
        config[:environment] = :production
      end
      Rack::MockRequest.new(Middleman::Rack.new(app).to_app)
    end
  end

  def test_get_and_head_lengths_for_rewritten_pages_and_static_assets
    paths = %w[/ /partners/ /job_boards/ /job_boards/direct_apply/
               /company_webhooks/ /stylesheets/screen.css /stylesheets/print.css
               /javascripts/all.js /images/logo.png /fonts/slate.woff
               /images/default_key.png /does-not-exist.html]
    paths.each do |path|
      get = self.class.request.get(path)
      head = self.class.request.head(path)
      assert_equal(path.include?('does-not-exist') ? 404 : 200, get.status, path)
      assert_equal get.body.bytesize.to_s, get['Content-Length'], path
      assert_equal get.status, head.status, path
      assert_equal get['Content-Length'], head['Content-Length'], path
      assert_empty head.body, path
      if path.start_with?('/images/', '/fonts/')
        assert_equal File.binread("source#{path}"), get.body.b, path
      end
    end
  end

  def test_bypassed_html_keeps_upstream_length
    options = { 'bypass_inline_url_rewriter' => 'true' }
    get = self.class.request.get('/partners/', options)
    head = self.class.request.head('/partners/', options)
    assert_equal 200, get.status
    assert_equal get.body.bytesize.to_s, get['Content-Length']
    assert_equal get.status, head.status
    assert_equal get['Content-Length'], head['Content-Length']
    assert_empty head.body
  end

  # A small header exercises the Range-count guard without resource exhaustion.
  def test_excessive_ranges_are_ignored
    path = '/images/logo.png'
    whole = File.binread("source#{path}")
    options = { 'HTTP_RANGE' => 'bytes=' + Array.new(101, '0-0').join(',') }
    assert_nil Rack::Utils.get_byte_ranges(options['HTTP_RANGE'], whole.bytesize)
    get = self.class.request.get(path, options)
    head = self.class.request.head(path, options)
    assert_equal 200, get.status
    assert_equal whole, get.body.b
    assert_equal whole.bytesize.to_s, get['Content-Length']
    assert_nil get['Content-Range']
    assert_equal get.status, head.status
    assert_equal get['Content-Length'], head['Content-Length']
    assert_empty head.body
  end

  def test_binary_ranges_and_unsatisfiable_ranges
    %w[/images/logo.png /fonts/slate.woff /images/default_key.png].each do |path|
      whole = File.binread("source#{path}")
      options = { 'HTTP_RANGE' => 'bytes=10-29' }
      get = self.class.request.get(path, options)
      head = self.class.request.head(path, options)
      assert_equal 206, get.status, path
      assert_equal whole.byteslice(10, 20), get.body.b, path
      assert_equal '20', get['Content-Length'], path
      assert_equal "bytes 10-29/#{whole.bytesize}", get['Content-Range'], path
      assert_equal get.status, head.status, path
      assert_equal get['Content-Length'], head['Content-Length'], path
      assert_equal get['Content-Range'], head['Content-Range'], path
      assert_empty head.body, path

      options = { 'HTTP_RANGE' => 'bytes=999999999-' }
      get = self.class.request.get(path, options)
      head = self.class.request.head(path, options)
      assert_equal 416, get.status, path
      assert_equal "bytes */#{whole.bytesize}", get['Content-Range'], path
      assert_equal get.status, head.status, path
      assert_equal get['Content-Length'], head['Content-Length'], path
      assert_equal get['Content-Range'], head['Content-Range'], path
      assert_empty head.body, path
    end
  end
end
