require 'line/bot'
require "tempfile"
require "sinatra"
require 'google-cloud-vision'

get '/' do
  'hello world!'
end

post "/callback" do
  body = request.body.read
  signature = request.env["HTTP_X_LINE_SIGNATURE"]

  # unless client.validate_signature(body, signature)
  #   puts 'signature_error'
  #   error 400 do
  #     "Bad Request"
  #   end
  # end

  events = client.parse_events_from(body)
  events. each do |e|
    next unless e == Line::Bot::Event::Message ||  e.type == Line::Bot::Event::MessageType::Image

    response = @client.get_message_content(e.message['id'])
    case response
    when Net::HTTPSuccess
      tempfile = Tempfile.new(["tempfile", '.jpg']).tap do |file|
        file.write(response.body)
      end

      begin
        results = face_detection_results(tempfile.path)
        messages = results.map{ |result| { type: 'text', text: result } }
        client.reply_message(e['replyToken'], messages)
      rescue => e
        puts e.message
        client.reply_message(e['replyToken'], {
          type: 'text',
          text: "解析に失敗しました"
        })
      end
    else
      puts response.code
      puts response.body
      client.reply_message(e['replyToken'], {
        type: 'text',
        text: 'ネットワークエラー'
      })
    end
  end

  "OK"
end


def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_id = ENV["LINE_CHANNEL_ID"]
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def face_detection_results(image_path)
  image_annotator = Google::Cloud::Vision.image_annotator

  response = image_annotator.face_detection(
    image:       image_path,
    max_results: 5
  )

  likelihood = {
    :UNKNOWN => 'UNKNOWN',
    :VERY_UNLIKELY => '＊',
    :UNLIKELY => '＊＊',
    :POSSIBLE => '＊＊＊',
    :LIKELY => '＊＊＊＊',
    :VERY_LIKELY => '＊＊＊＊＊',
  }

  response.responses.map do |res|
    res.face_annotations.map do |annotation|
      [
        "喜び：#{likelihood[annotation.joy_likelihood]}\n悲しみ：#{likelihood[annotation.sorrow_likelihood]}\n怒り：#{likelihood[annotation.anger_likelihood]}\n驚き：#{likelihood[annotation.surprise_likelihood]}\n検出制度：#{annotation.detection_confidence}"
      ]
    end
  end.flatten
end
