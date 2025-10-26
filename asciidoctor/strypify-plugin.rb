require 'digest/md5'
require 'fileutils'
require 'tempfile'
require 'rbconfig'

HOST_OS = RbConfig::CONFIG['host_os']
STRYPIFY_CMD =
  if HOST_OS =~ /mswin|mingw|cygwin/
    "Strypify.exe"
  elsif HOST_OS =~ /darwin/
    "/Applications/Strypify.app/Contents/MacOS/Strypify"
  else
    strypify_cmd = "Strypify"
  end


class StrypeSyntaxHighlighter < Asciidoctor::Extensions::BlockProcessor
  enable_dsl
  on_context :listing
  positional_attributes 'language'

  def process parent, reader, attrs
    imageCacheDir = '.image-cache'
    src = reader.readlines.join("\n")
    unless File.directory?(imageCacheDir)
      FileUtils.mkdir_p(imageCacheDir)
    end
    filename = "#{imageCacheDir}/strype-#{Digest::MD5.hexdigest(src)}.png"
    imgAttr = {}
    imgAttr["target"] = filename
    if not File.file?(filename)
        file = Tempfile.new('temp-strype-src')
        begin
          file.write src
          file.close

          Dir.chdir(imageCacheDir){
            %x(#{STRYPIFY_CMD} --file=#{file.path} --no-sandbox --disable-setuid-sandbox --force-color-profile=srgb)
          }
        ensure
          file.delete
        end
    end
    create_image_block parent, imgAttr
  end
end

Asciidoctor::Extensions.register do
  block StrypeSyntaxHighlighter, :strype
end