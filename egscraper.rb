require 'yaml'
require 'time'
require 'net/http'
require 'json'
require_relative 'queries'

class FreeGames
  PROMO = 'https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=en-US&country=RU&allowCountries=RU'.freeze
  GQL = 'https://www.epicgames.com/graphql'.freeze
  GAME_INFO_RU = 'https://store-content.ak.epicgames.com/api/ru/content/products/'.freeze
  GAME_INFO = 'https://store-content.ak.epicgames.com/api/en-US/content/products/'.freeze
  PRODUCT = 'https://www.epicgames.com/store/ru/product/'.freeze

  class << self
    def games_get
      games_hash = Requests.get(PROMO, content: 'application/json;charset=utf-8')
      games_hash.dig('data', 'Catalog', 'searchStore', 'elements')
    end

    def promotions_get
      free_games = games_get
      current_promotions = []
      upcoming_promotions = []
      free_games.each do |game|
        promo = game.dig('promotions', 'promotionalOffers')
        up_promo = game.dig('promotions', 'upcomingPromotionalOffers')
        current_promotions.push game if promo && !promo.empty?
        upcoming_promotions.push game if up_promo && !up_promo.empty?
      end
      [current_promotions, upcoming_promotions]
    end
  end

  class Requests
    class << self
      def get(uri_string, **options)
        uri = URI.parse(uri_string)
        request = Net::HTTP::Get.new(uri)

        request['Accept'] = 'application/json, text/plain, */*'
        request['Content-Type'] ||= options[:content]

        secure = { use_ssl: uri.scheme == 'https' }

        response = Net::HTTP.start(uri.hostname, uri.port, secure) do |http|
          http.request(request)
        end

        JSON.parse(response.body)
      end

      def post(uri_string, **options)
        uri = URI.parse(uri_string)
        request = Net::HTTP::Post.new(uri)

        request['Accept'] = 'application/json, text/plain, */*'
        request['Content-Type'] ||= options[:content]
        request.body ||= options[:body]

        secure = { use_ssl: uri.scheme == 'https' }

        response = Net::HTTP.start(uri.hostname, uri.port, secure) do |http|
          http.request(request)
        end

        JSON.parse(response.body)
      end
    end
  end

  class Attributes
    class << self
      def runner
        promotions = FreeGames.promotions_get
        p promotions
        # ids = ids_get(promotions)
        # ids = ['dungeons-3', 'mudrunner', 'assassins-creed-valhalla', 'solitairica']
        # ids = ['assassins-creed-valhalla']
        # main_games = main_game_get(ids)
        # p main_games
        # p main_games.count
        # titles = titles_get(main_games)
        # p titles

        # pubs_n_devs = pubs_n_devs_get(promotions)
        # p pubs_n_devs
        # dates = dates_get(promotions)
        # p dates
        # descriptions = descriptions_get(main_games)
        # p descriptions
        # price = price_get(promotions)
        # p price
        # ratings = ratings_get(ids)
        # p ratings
        # videos = videos_get(main_games)
        # p videos
        # images = images_get(main_games)
        # p images
        # languages = languages_get(main_games)
        # p languages
        # hw = hardware_get(main_games)
        # p hw
      end

      def ids_get(games)
        slugs = games.flatten.map { |game| game['productSlug'] }
        slugs.map { |game| game.chomp('/home')[/[-[:alnum:]]+/] } # %r{^[^\/]}
      end

      def price_get(games)
        games.map do |game|
          game.first.dig('price', 'totalPrice', 'fmtPrice', 'originalPrice')
        end
      end

      def pubs_n_devs_get(games)
        devs = games.map do |game|
          dev_hash = game.first['customAttributes'].map { |split_hash| [split_hash.values].to_h }
          dev_hash.find_all { |dev| dev['developerName'] || dev['publisherName'] }
        end
        devs.map { |dev| dev.map(&:values).flatten.join(' / ') }
      end

      def ratings_get(ids)
        ratings = []
        ids.each do |id|
          query = { query: RATINGS, variables: { sku: "EPIC_#{id}" } }.to_json
          ratings.push(
            Requests.post(GQL, body: query, content: 'application/json;charset=utf-8')
          )
          sleep rand(0.75..1.5)
        end
        score = ratings.map { |e| e.dig('data', 'OpenCritic', 'productReviews', 'openCriticScore') || '-' }
        percent = ratings.map { |e| e.dig('data', 'OpenCritic', 'productReviews', 'percentRecommended') || '-' }
        [score, percent].transpose
      end

      def game_info_get(ids)
        games = []
        ids.each do |id|
          games.push Requests.get(GAME_INFO + id) if id
          sleep rand(0.75..1.5)
        end
        games
      end

      def main_game_get(ids)
        games = game_info_get(ids)
        main_games = []
        games.each do |game|
          # p game['pages']
          game['pages'].each do |product|
            main_games.push product if product['type'] == 'productHome'
          end
        end
        main_games
      end

      def refs_get(game_info)
        refs = []
        game_info.each do |game|
          game_ref = (game.dig('data', 'carousel', 'items').first.dig('video', 'recipes') || nil)
          refs.push YAML.safe_load(game_ref)
        end

        en_refs = refs.map { |ref| ref['en-US'] unless ref.nil? }
        webm = en_refs.map { |game| game&.select { |ref| ref['recipe'] == 'video-webm' } }
        webm.map { |game| game&.map { |webm_ref| webm_ref['mediaRefId'] } }
      end

      def videos_get(game_info)
        vid_attrs = []
        media_refs = refs_get(game_info).flatten
        media_refs.each do |ref|
          if ref.nil?
            vid_attrs.push ref
            next
          end

          query = { query: MEDIA, variables: { mediaRefId: ref } }.to_json
          vid_attrs.push(
            Requests.post(GQL, body: query, content: 'application/json;charset=utf-8')
          )
          sleep rand(0.75..1.5)
        end
        videos = vid_attrs.map { |attr| attr&.dig('data', 'Media', 'getMediaRef', 'outputs') }
        high_res_videos = videos.map { |video| video&.find_all { |e| e['key'] == 'high' } }.flatten
        high_res_videos.map { |video| video['url'] unless video.nil? }
      end

      def descriptions_get(game_info)
        descriptions = []
        game_info.each do |game|
          full_desc = game.dig('data', 'about', 'description') || '-'
          short_desc = game.dig('data', 'about', 'shortDescription')
          descriptions.push [full_desc, short_desc]
        end
        descriptions.map { |desc_pair| desc_pair.map { |desc| desc[/[^)].+/m].strip } } # [/(?<=\))?(.)+/m]
      end

      def images_get(game_info)
        images = []
        game_info.each do |game|
          images.push(game['_images_'].find_all { |image| /\.png$/.match(image) }.first)
        end
        images
      end

      def requirements_get(game_info)
        game_info.map { |game| game.dig('data', 'requirements') }
      end

      def languages_get(game_info)
        requirements_get(game_info).map { |req| req['languages'].join.strip }
      end

      def hardware_get(game_info)
        requirements_fmt = String.new
        requirements = requirements_get(game_info).map { |e| e['systems'] }
        os_types = requirements.map { |os| os.map { |spec| spec['systemType'] } }.flatten
        req_details = requirements.map { |os| os.map { |spec| spec['details'] } }.flatten(1)
        req_details.each_with_index do |os, i|
          requirements_fmt << os_types[i] + "\n" 
          os.each do |spec|
            title = spec['title']
            min = spec['minimum']
            rec = spec['recommended']
            # if title == 'Место на диске' && /\d$/.match(rec)
            #   rec + 'ГБ'
            # elsif title == 'Место на диске' && /\d$/.match(min)
            #   min + 'ГБ'
            # end
            if min == rec
              requirements_fmt << (title + ': ' + rec) << "\n"
            elsif min && (!rec || rec.empty?)
              requirements_fmt << (title + ': ' + min) << "\n"
            elsif rec && (!min || min.empty?)
              requirements_fmt << (title + ': ' + rec) << "\n"
            else
              requirements_fmt << (title + ': ' + min + ' | ' + rec) << "\n"
            end
          end
          requirements_fmt << "\n"
        end
        requirements_fmt.split("\n\n")
      end

      def dates_get(games)
        games.map do |game|
          cur_promo = game.first['promotions']['promotionalOffers']
          up_promo = game.first['promotions']['upcomingPromotionalOffers']
          promo = (cur_promo.empty? ? up_promo : cur_promo).first
          offers = promo['promotionalOffers'].first
          # promo = game.first['promotions'].values.flatten.first
          # offers = promo['promotionalOffers'].first
          to_msk = proc { |date| (Time.parse(date) + 60 * 60 * 3).strftime('%d/%m/%Y %H:%M MSK') }
          [offers['startDate'], offers['endDate']].map(&to_msk)
        end
      end

      def titles_get(games)
        games.map { |game| game.dig('data', 'navTitle').strip } #.compact
      end

      def urls_get(ids)
        ids.map { |id| PRODUCT + id }
      end
    end
  end
end

FreeGames::Attributes.runner
# Social?
# test
