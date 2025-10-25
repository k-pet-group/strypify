require 'digest/md5'
require 'fileutils'
require 'tempfile'

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
            if ENV['OS'] == 'Windows_NT'
              # Assume it's on PATH:
              %x(Strypify.exe --file=#{file.path})
            else
              %x(/Applications/Strypify.app/Contents/MacOS/Strypify --file=#{file.path})
            end
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