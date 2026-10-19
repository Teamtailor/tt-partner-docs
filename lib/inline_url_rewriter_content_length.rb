# Backport of the middleman-core 4.3 fix for Rack >= 2.1.
#
# InlineURLRewriter (used by relative_assets) rewrites response bodies but
# keeps the upstream Content-Length header. Rack 2.0 recomputed it when the
# rewritten body was wrapped in a Rack::Response; Rack 2.1+ does not, so
# Rack::Lint rejects the response and `middleman build` fails. Middleman 4.3
# resets the header itself, so this patch only applies to older versions.
require 'middleman-core/version'
require 'middleman-core/core_extensions/inline_url_rewriter'

if Gem::Version.new(Middleman::VERSION) < Gem::Version.new('4.3.0')
  module InlineURLRewriterContentLength
    def call(env)
      status, headers, body = super

      if body.is_a?(Array) && headers.key?('Content-Length')
        headers['Content-Length'] = body.sum { |part| part.to_s.bytesize }.to_s
      end

      [status, headers, body]
    end
  end

  Middleman::CoreExtensions::InlineURLRewriter::Rack.prepend(InlineURLRewriterContentLength)
end
