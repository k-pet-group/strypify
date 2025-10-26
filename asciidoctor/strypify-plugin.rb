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
    strypify_cmd = "strypify-headless.sh"
  end


class StrypeSyntaxHighlighter < Asciidoctor::Extensions::BlockProcessor
  enable_dsl
  on_context :listing
  positional_attributes 'language'

  def process parent, reader, attrs
    # Must put image cache inside output dir so relative paths work:
    imageCacheDirName = '.image-cache'
    imageCacheDirPath = File.join(parent.document.attr('outdir'), imageCacheDir)
    src = reader.readlines.join("\n")
    unless File.directory?(imageCacheDirPath)
      FileUtils.mkdir_p(imageCacheDirPath)
    end
    filename = "#{imageCacheDirName}/strype-#{Digest::MD5.hexdigest(src)}.png"
    imgAttr = {}
    imgAttr["target"] = filename
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
    create_image_block parent, imgAttr
  end
end

Asciidoctor::Extensions.register do
  block StrypeSyntaxHighlighter, :strype
end