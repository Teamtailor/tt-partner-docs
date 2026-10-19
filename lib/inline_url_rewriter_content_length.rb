# Backport of the middleman-core 4.3 fix for Rack >= 2.1.
#
# InlineURLRewriter (used by relative_assets) rewrites response bodies but
# keeps the upstream Content-Length header. Rack 2.0 recomputed it when the
# rewritten body was wrapped in a Rack::Response; Rack 2.1+ does not, so
# Rack::Lint rejects the response and `middleman build` fails. Keep the
# original bypass paths and update the header only for rewritten bytes.
require 'middleman-core/version'
require 'middleman-core/core_extensions/inline_url_rewriter'

if Gem::Version.new(Middleman::VERSION) < Gem::Version.new('4.3.0')
  module InlineURLRewriterContentLength
    def call(env)
      status, headers, response = @rack_app.call(env)

      # Allow configuration or upstream request to skip all rewriting
      return [status, headers, response] if env['bypass_inline_url_rewriter'] == 'true'

      path = ::Middleman::Util.full_path(env['PATH_INFO'], @middleman_app)

      return [status, headers, response] unless path =~ /(^\/$)|(#{@source_exts_regex_text}$)/
      return [status, headers, response] unless body = ::Middleman::Util.extract_response_text(response)

      dirpath = ::Pathname.new(File.dirname(path))

      rewritten = ::Middleman::Util.instrument 'inline_url_rewriter', path: path do
        ::Middleman::Util.rewrite_paths(body, path, @all_asset_exts, @middleman_app) do |asset_path|
          uri = ::Middleman::Util.parse_uri(asset_path)

          relative_path = uri.host.nil?

          full_asset_path = if relative_path
            dirpath.join(asset_path).to_s
          else
            asset_path
          end

          @rewriters.each do |rewriter|
            uid = rewriter.fetch(:id)

            # Allow upstream request to skip this specific rewriting
            next if env["bypass_inline_url_rewriter_#{uid}"] == 'true'

            exts = rewriter.fetch(:url_extensions)
            next unless exts.include?(::File.extname(asset_path))

            source_exts = rewriter.fetch(:source_extensions)
            next unless source_exts.include?(::File.extname(path))

            ignore = rewriter.fetch(:ignore)
            next if ignore.any? { |r| ::Middleman::Util.should_ignore?(r, full_asset_path) }

            rewrite_ignore = Array(rewriter[:rewrite_ignore] || [])
            next if rewrite_ignore.any? { |i| ::Middleman::Util.path_match(i, path) }

            proc = rewriter.fetch(:proc)

            result = proc.call(asset_path, dirpath, path)
            asset_path = result if result
          end

          asset_path
        end
      end

      headers['Content-Length'] = rewritten.bytesize.to_s

      ::Rack::Response.new(
        rewritten,
        status,
        headers
      ).finish
    end
  end

  Middleman::CoreExtensions::InlineURLRewriter::Rack.prepend(InlineURLRewriterContentLength)
end
