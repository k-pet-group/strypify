require 'digest/md5'
require 'fileutils'
require 'tempfile'
require 'rbconfig'

host_os = RbConfig::CONFIG['host_os']
strypify_cmd = "Strypify"

if host_os =~ /mswin|mingw|cygwin/
  strypify_cmd = "Strypify.exe"
elsif host_os =~ /darwin/
  stryipfy_cmd = "/Applications/Strypify.app/Contents/MacOS/Strypify"
elsif host_os =~ /linux/
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
            %x(#{strypify_cmd} --file=#{file.path})
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