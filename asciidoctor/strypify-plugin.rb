require 'digest/md5'
require 'fileutils'
require 'tempfile'
require 'rbconfig'
require 'zlib'
require 'base64'
require 'open3'

HOST_OS = RbConfig::CONFIG['host_os']
STRYPIFY_CMD =
  if HOST_OS =~ /mswin|mingw|cygwin/
    "Strypify.exe"
  elsif HOST_OS =~ /darwin/
    "/Applications/Strypify.app/Contents/MacOS/Strypify"
  else
    "strypify-headless.sh"
  end

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

    # 2. Try syntax check
    output = `#{python_cmd} -m py_compile #{file} 2>&1`
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
    md5 = Digest::MD5.hexdigest(src)
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
                    stdout, stderr, status = Open3.capture3(STRYPIFY_CMD, "--file=#{file.path}", "--output-file=#{justFilename}", "--editor-url=#{strype_url}")

                    unless status.success?
                      return create_block(parent, :paragraph, "Strypify failed (exit #{status.exitstatus}), stdout: #{stdout}, stderr: #{stderr}", {})
                    end
                    sleep(1)
                    # Copy it to central cache, since it wasn't there:
                    FileUtils.cp(justFilename, centralFilename)
                  }
              else
                return create_block(parent, :paragraph, "Invalid Python: " + syntax_err.gsub(file.path, "Strype block #{line_info}"), {})
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

    if open_link
      base64_encoded = encode_for_url(src)
      link_block = create_inline parent, :anchor, "Open", type: :link, target: "#{strype_url}?shared_proj_id=spy:#{base64_encoded}", attributes: { 'window' => '_blank' }
      parent << image
      parent << link_block

      nil  # return nil because we've inserted blocks ourselves
    else
      image
    end
  end
end

Asciidoctor::Extensions.register do
  block StrypeSyntaxHighlighter, :strype
end