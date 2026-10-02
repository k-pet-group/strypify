require 'digest/md5'
require 'fileutils'
require 'tempfile'
require 'rbconfig'
require 'zlib'
require 'base64'
require 'open3'
require 'securerandom'
require 'shellwords'

HOST_OS = RbConfig::CONFIG['host_os']
STRYPIFY_CMD =
  if HOST_OS =~ /mswin|mingw|cygwin/
    "Strypify.exe"
  elsif HOST_OS =~ /darwin/
    "/Applications/Strypify.app/Contents/MacOS/Strypify"
  else
    "strypify-headless.sh"
  end

# On Linux (headless, via xvfb-run), Strypify/Electron startup can in rare
# cases hang outright rather than crash, and Open3.capture3 has no timeout
# of its own -- a hang there would block the whole build forever. Wrap with
# the standard `timeout` utility (present on any Linux CI/production host
# this realistically runs on) so a genuine hang fails loudly instead.
STRYPIFY_TIMEOUT_PREFIX = (HOST_OS =~ /darwin|mswin|mingw|cygwin/) ? [] : ["timeout", "--signal=KILL", "300"]

VERSION = %x(#{STRYPIFY_CMD} --version).strip

class StrypeSyntaxHighlighter < Asciidoctor::Extensions::BlockProcessor
  enable_dsl
  on_context :listing

  def embed_images(input, images_dir)
    input.gsub(/\$\{([^}]+)\}/) do
      filename = Regexp.last_match(1)

      if File.exist?(filename)
        # Fine, no processing needed
      elsif File.exist?(File.join(images_dir, filename))
        filename = File.join(images_dir, filename)
      else
        raise "File not found in current dir or in #{images_dir}: #{filename}"
      end

      ext = File.extname(filename).sub('.', '') # "png", "jpg", etc.
      data = File.read(filename, mode: "rb")
      encoded = Base64.strict_encode64(data)

      %Q{load_image("data:image/#{ext};base64,#{encoded}")}
    end
  end

  def python_syntax_error(file)
    # 1. Check if Python is available
    python_cmd = nil
    null_dev = Gem.win_platform? ? 'NUL' : '/dev/null'

    ['python', 'python3', 'py'].each do |cmd|
      if system("#{cmd} --version > #{null_dev} 2>&1") || system("#{cmd} --version > #{null_dev} 2>&1")
        python_cmd = cmd
        break
      end
    end

    # If no Python, return nil (assume valid)
    return nil unless python_cmd

    # 2. Try syntax check. Deliberately use ast.parse rather than `-m py_compile`:
    # py_compile's whole purpose is to write a .pyc, and it does so into a shared
    # pycache dir regardless of PYTHONDONTWRITEBYTECODE (that variable only
    # suppresses bytecode caching for normal script execution/import, not an
    # explicit py_compile call). A write there can fail with a permission error
    # unrelated to the actual Python syntax, which would otherwise be
    # misreported below as an "Invalid Python" error. ast.parse performs the
    # same syntax check with no filesystem side effects at all.
    ast_check = <<~PYTHON
      import ast, sys, traceback
      try:
          ast.parse(open(sys.argv[1], 'rb').read(), filename=sys.argv[1])
      except SyntaxError as e:
          sys.stderr.write(''.join(traceback.format_exception_only(e)))
          sys.exit(1)
    PYTHON
    output = `#{python_cmd} -c #{ast_check.shellescape} #{file} 2>&1`
    return nil if $?.success?

    # 3. Return the error output
    output.strip
  end

  def encode_for_url(str)
    z = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
    compressed = z.deflate(str, Zlib::FINISH)
    z.close
    Base64.urlsafe_encode64(compressed)
  end

  def process parent, reader, attrs
    line_info = reader.cursor.line_info
    strype_url = attrs['strype_url'] || parent.document.attr('strype_url') || 'https://strype.org/editor/'
    open_link = (attrs['open_link'] == 'true' || attrs.values.include?('open_link')) || parent.document.attr('open_link') || nil
    images_dir = parent.document.attr('imagesdir') || ''
    width_factor = attrs['width_factor'] || parent.document.attr('width_factor') ||  '1'
    frame_header_contains = attrs['frame_header_contains'] || parent.document.attr('frame_header_contains') || ''

    # Central cache:
    centralImageCacheDirPath = File.join(Dir.home, ".strypify-image-cache")
    Dir.mkdir(centralImageCacheDirPath) unless Dir.exist?(centralImageCacheDirPath)

    # Must put image cache inside output dir so relative paths work:
    imageCacheDirName = '.image-cache'
    imageCacheDirPath = File.join(parent.document.attr('outdir') || ".", imageCacheDirName)
    src = embed_images(reader.readlines.join("\n"), images_dir)
    unless File.directory?(imageCacheDirPath)
      FileUtils.mkdir_p(imageCacheDirPath)
    end
    md5 = Digest::MD5.hexdigest(src + width_factor + frame_header_contains)
    justFilename = "strype-strypify#{VERSION}-#{md5}.png"
    localFilename = "#{imageCacheDirPath}/#{justFilename}"
    relativeFilename = "#{imageCacheDirName}/#{justFilename}"
    centralFilename = File.join(centralImageCacheDirPath, justFilename)

    # Pass title through so that it properly treats it like a figure caption when making the block:
    # Also pass id through, and some other items:
    imgAttr = attrs.slice("id", "title", "alt", "width", "height", "scale", "align", "role", "opts")
    # Cancel out images_dir:
    imgAttr["target"] = if images_dir.empty?
                   relativeFilename
                 else
                   # Count path components and prepend that many ".."
                   images_dir.split('/').map { '..' }.join('/') + '/' + relativeFilename
                 end
    imgAttr["alt"] = "Strype code" unless imgAttr.key?("alt")


    if not File.file?(localFilename)
        # Do we have it in the central cache?
        if File.file?(centralFilename)
            # Yes; copy it from there:
            FileUtils.cp(centralFilename, localFilename)
        else
            file = Tempfile.new('temp-strype-src')
            begin
              # Important to use binary mode so \n doesn't get turned into \r\n on Windows (which upsets MD5 hash):
              file.binmode
              file.write src
              file.close

              syntax_err = python_syntax_error(file.path)

              unless syntax_err
                  Dir.chdir(imageCacheDirPath){
                    frame_header_opt = frame_header_contains.empty? ? [] : ["--frame-header-contains=#{frame_header_contains}"]
                    # Render to a per-call unique filename rather than directly to justFilename:
                    # two concurrent asciidoctor processes can end up rendering the same
                    # (identically-hashed) code block at once, and since the content is
                    # identical either render is equally valid, so there is no need to make
                    # them contend for the same output path -- just let whichever finishes
                    # first move its result into place.
                    # Keep the .png suffix (rather than appending after it) -- Strypify
                    # may branch on the output file's extension internally.
                    tempOutputFilename = "#{justFilename.sub(/\.png\z/, '')}-tmp-#{Process.pid}-#{SecureRandom.hex(8)}.png"
                    begin
                      stdout, stderr, status = Open3.capture3(*STRYPIFY_TIMEOUT_PREFIX, STRYPIFY_CMD, "--file=#{file.path}", "--output-file=#{tempOutputFilename}", "--editor-url=#{strype_url}", "--hide-errors", "--width-factor=#{width_factor}", *frame_header_opt)

                      # Judge success by whether a real output file was written, not by the
                      # process exit status: on some headless Linux hosts, Strypify/Electron
                      # can crash during its own window/GTK teardown *after* it has already
                      # written the output file, which makes the process exit non-zero despite
                      # having done its job correctly. Treating that as a build failure would
                      # be a false positive, so only a missing/empty output file is a real
                      # failure here.
                      unless File.file?(tempOutputFilename) && File.size(tempOutputFilename) > 0
                        raise "Strypify failed (exit #{status.exitstatus}) for Strype block #{line_info}, stdout: #{stdout}, stderr: #{stderr}"
                      end
                      sleep(1)
                      FileUtils.mv(tempOutputFilename, justFilename)
                    ensure
                      File.delete(tempOutputFilename) if File.file?(tempOutputFilename)
                    end
                    # Copy it to central cache, since it wasn't there:
                    FileUtils.cp(justFilename, centralFilename)
                  }
              else
                raise "Invalid Python in Strype block #{line_info}: " + syntax_err.gsub(file.path, "Strype block #{line_info}")
              end

            ensure
              file.delete
            end
        end
    elsif not File.file?(centralFilename)
        # In local, but not central, take a copy:
        FileUtils.cp(localFilename, centralFilename)
    end

    image = create_image_block parent, imgAttr
    # Default is to centre:
    image.add_role 'text-center'
    image.add_role 'strype-code-image'

    desc = nil
    if parent.document.backend == 'html5'
      code = src.gsub(/load_image\("data:[^"]+"\)/, "image_literal")
      # The style below makes a "physically invisible" element that will still show up for
      # screen readers to take notice of (they ignore hidden elements or display:none, etc)
      html = <<~HTML
        <div id="fullcode-#{md5}" style="position:absolute;width:1px;height:1px;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;">
         <pre><code>#{code}</code></pre>
        </div>
      HTML
      desc = create_block parent, :pass, html, {}
    end

    if open_link
      base64_encoded = encode_for_url(src)
      link_block = create_inline parent, :anchor, "Open", type: :link, target: "#{strype_url}?shared_proj_id=spy:#{base64_encoded}", attributes: { 'window' => '_blank' }
      parent << image
      parent << desc if desc
      parent << link_block
      nil  # return nil because we've inserted blocks ourselves
    else
      parent << image
      parent << desc if desc
      nil
    end
  end
end

Asciidoctor::Extensions.register do
  block StrypeSyntaxHighlighter, :strype

  postprocessor do
      process do |doc, output|
        next output unless doc.backend == 'html5'

        output.gsub(/<img[^>]*src="[^"]+strype-strypify[^"]+-([0-9a-z]+)\.png"[^>]*>/) do |img|
          md5 = Regexp.last_match(1)
          if img.include? 'aria-describedby='
            img
          else
            img.sub(/>$/, " aria-describedby=\"fullcode-#{md5}\">")
          end
        end
      end
    end
end