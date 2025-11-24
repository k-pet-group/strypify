require 'digest/md5'
require 'fileutils'
require 'tempfile'
require 'rbconfig'
require 'zlib'
require 'base64'


HOST_OS = RbConfig::CONFIG['host_os']
STRYPIFY_CMD =
  if HOST_OS =~ /mswin|mingw|cygwin/
    "Strypify.exe"
  elsif HOST_OS =~ /darwin/
    "/Applications/Strypify.app/Contents/MacOS/Strypify"
  else
    strypify_cmd = "strypify-headless.sh"
  end


class StrypeSyntaxHighlighter < Asciidoctor::Extensions::BlockProcessor
  enable_dsl
  on_context :listing

  def encode_for_url(str)
    z = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
    compressed = z.deflate(str, Zlib::FINISH)
    z.close
    Base64.urlsafe_encode64(compressed)
  end

  def process parent, reader, attrs
    strype_url = attrs['strype_url'] || parent.document.attr('strype_url') || 'https://strype.org/editor/'
    open_link = (attrs['open_link'] == 'true' || attrs.values.include?('open_link')) || parent.document.attr('open_link') || nil

    # Must put image cache inside output dir so relative paths work:
    imageCacheDirName = '.image-cache'
    imageCacheDirPath = File.join(parent.document.attr('outdir') || ".", imageCacheDirName)
    src = reader.readlines.join("\n")
    unless File.directory?(imageCacheDirPath)
      FileUtils.mkdir_p(imageCacheDirPath)
    end
    filename = "#{imageCacheDirName}/strype-#{Digest::MD5.hexdigest(src)}.png"
    # Pass title through so that it properly treats it like a figure caption when making the block:
    # Also pass id through:
    imgAttr = attrs.slice("id", "title")
    # Add a marker so we can remove any added imagesdir later (using postprocessor added at end of this file):
    imgAttr["target"] = "SKIPIMAGESDIR/" + filename

    if not File.file?(filename)
        file = Tempfile.new('temp-strype-src')
        begin
          file.write src
          file.close

          Dir.chdir(imageCacheDirPath){
            %x(#{STRYPIFY_CMD} --file=#{file.path})
          }
        ensure
          file.delete
        end
    end

    image = create_image_block parent, imgAttr
    # Default is to centre:
    image.add_role 'text-center'

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

  postprocessor do
    process do |document, output|
      # Remove SKIPIMAGESDIR and any image dir path placed before it:
      output.gsub(%r{"[^"]*SKIPIMAGESDIR/}, '"')
    end
  end
end