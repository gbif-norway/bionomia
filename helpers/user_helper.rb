# encoding: utf-8

module Sinatra
  module Bionomia
    module Helper
      module UserHelper

        def search_user
          @results = []
          searched_term = params[:q]
          return if !searched_term.present?

          page = (params[:page] || 1).to_i
          limit = (params[:limit] || 30).to_i
          is_public = params[:is_public] || ""
          has_occurrences = params[:has_occurrences] || ""

          opts = {}
          if is_public.downcase == "true" || is_public.downcase == "on"
            opts[:is_public] = true
          elsif is_public.downcase == "false"
            opts[:is_public] = false
          end
          if has_occurrences.downcase == "true" || has_occurrences.downcase == "on"
            opts[:has_occurrences] = true
          elsif has_occurrences.downcase == "false"
            opts[:has_occurrences] = false
          end

          client = Elasticsearch::Client.new(
            url: Settings.elastic.server,
            request_timeout: 5*60,
            retry_on_failure: true,
            reload_on_failure: true,
            reload_connections: 1_000,
            adapter: :typhoeus
          )
          body = build_name_query(searched_term, opts)
          from = (page -1) * limit

          response = client.search index: Settings.elastic.user_index, from: from, size: limit, body: body
          results = response["hits"].deep_symbolize_keys

          @pagy = Pagy.new(count: results[:total][:value], items: limit, page: page)
          @results = results[:hits]
        end

        def search_user_country
          @results = []
          country_code = params[:country_code]
          action = params[:action] && !params[:action].blank? ? params[:action] : nil
          family = params[:q] && !params[:q].blank? ? params[:q] : nil

          return if action && !["identified","collected"].include?(action)

          action = "recorded" if action == "collected"
          page = (params[:page] || 1).to_i
          limit = (params[:limit] || 30).to_i

          client = Elasticsearch::Client.new(
            url: Settings.elastic.server,
            request_timeout: 5*60,
            retry_on_failure: true,
            reload_on_failure: true,
            reload_connections: 1_000,
            adapter: :typhoeus
          )
          body = build_user_country_query(country_code, action, family)

          from = (page -1) * limit

          response = client.search index: Settings.elastic.user_index, from: from, size: limit, body: body
          results = response["hits"].deep_symbolize_keys

          @pagy = Pagy.new(count: results[:total][:value], items: limit, page: page)
          @results = results[:hits]
        end

        def search_user_taxa
          @results = []
          action = params[:action] && !params[:action].blank? ? params[:action] : nil
          family = params[:taxon] && !params[:taxon].blank? ? params[:taxon] : nil

          return if action && !["identified","collected"].include?(action)

          action = "recorded" if action == "collected" || action.nil?
          page = (params[:page] || 1).to_i
          limit = (params[:limit] || 30).to_i

          client = Elasticsearch::Client.new(
            url: Settings.elastic.server,
            request_timeout: 5*60,
            retry_on_failure: true,
            reload_on_failure: true,
            reload_connections: 1_000,
            adapter: :typhoeus
          )
          body = build_user_taxon_query(family, action)

          from = (page -1) * limit

          response = client.search index: Settings.elastic.user_index, from: from, size: limit, body: body
          results = response["hits"].deep_symbolize_keys

          @pagy = Pagy.new(count: results[:total][:value], items: limit, page: page)
          @results = results[:hits]
        end

        def find_user(id)
          if id.is_orcid?
            user = User.find_by_orcid(id)
          elsif id.is_wiki_id?
            user = User.find_by_wikidata(id)
          else
            user = User.find(id) rescue nil
          end
          if request && request.url.match(/.json$/)
            halt 404, {}.to_json if user.nil?
          else
            halt 404 if user.nil?
          end

          user
        end

        def create_user
          if params[:identifier] && !params[:identifier].empty?
            if DestroyedUser.where(identifier: params[:identifier]).exists?
              flash.next[:new_user] = { fullname: params[:identifier], slug: nil }
            elsif params[:identifier].is_orcid?
              new_user = User.find_or_create_by({ orcid: params[:identifier] })
              if new_user.nil?
                flash.next[:new_user] = { fullname: params[:identifier], slug: nil }
              else
                flash.next[:new_user] = { fullname: new_user.fullname, slug: new_user.orcid }
              end
            elsif params[:identifier].is_wiki_id?
              wiki_search = ::Bionomia::WikidataSearch.new
              user_data = wiki_search.wiki_user_data(params[:identifier])

              if user_data.nil?
                flash.next[:new_user] = { fullname: params[:identifier], slug: nil }
              else
                date_died = user_data[:date_died]
                date_born = user_data[:date_born]
                date_died_precision = user_data[:date_died_precision]
                date_born_precision = user_data[:date_born_precision]
                if  !(
                      ( !date_died.nil? && !date_died_precision.nil? ) ||
                      ( !date_born.nil? && !date_born_precision.nil? && Date.today.year - date_born.year >= 120 )
                    )
                  flash.next[:new_user] = { fullname: params[:identifier], slug: nil }
                # We have a user with that ORCID so switch to wikidata
                elsif user_data[:orcid] && User.where(orcid: user_data[:orcid]).exists?
                  user = User.find_by_orcid(user_data[:orcid])
                  user.orcid = nil
                  user.wikidata = params[:identifier]
                  user.save
                  user.reload
                  user.update_profile
                  user.flush_caches
                  DestroyedUser.create(identifier: user_data[:orcid], redirect_to: params[:identifier])
                  flash.next[:new_user] = { fullname: user.fullname, slug: user.wikidata }
                else
                  new_user = User.find_or_create_by({ wikidata: params[:identifier] })
                  if !new_user.valid_wikicontent?
                    flash.next[:new_user] = { fullname: params[:identifier], slug: nil }
                    new_user.delete_search
                    new_user.delete
                  else
                    flash.next[:new_user] = { fullname: new_user.fullname, slug: new_user.wikidata }
                  end
                end
              end
            else
              flash.next[:new_user] = { fullname: params[:identifier], slug: nil }
            end
          end
        end

        def user_stats(user)
          counts = user.country_counts
          cited = user.cited_specimens
          helped = user.helped_counts

          identified_count = counts.values.reduce(0) {
            |sum, val| sum + val[:identified]
          }
          recorded_count = counts.values.reduce(0) {
            |sum, val| sum + val[:recorded]
          }
          countries_identified = counts.each_with_object({}) do |code, data|
            if code[0] != "OTHER" && code[1][:identified] > 0
              data[code[0]] = code[1][:identified]
            end
          end
          countries_recorded = counts.each_with_object({}) do |code, data|
            if code[0] != "OTHER" && code[1][:recorded] > 0
              data[code[0]] = code[1][:recorded]
            end
          end

          {
            specimens: {
              total: user.all_occurrences_count,
              identified: identified_count,
              recorded: recorded_count,
              top_family_identified: user.top_family_identified,
              top_family_recorded: user.top_family_recorded
            },
            attributions: {
              helped: helped.count,
              number: helped.values.reduce(:+) || 0
            },
            countries: {
              identified: countries_identified,
              recorded: countries_recorded
            },
            articles: {
              specimens_cited: cited.select(:occurrence_id).distinct.count,
              number: cited.select(:article_id).distinct.count
            },
            recorded_bins: user.recorded_bins
                               .delete_if{|k,v| k > Date.today.year || k <= 1700 || v == 0}
                               .map{|k,v| [k.to_s, v]},
            identified_bins: user.identified_bins
                                 .delete_if{|k,v| k > Date.today.year || k <= 1700 || v == 0}
                                 .map{|k,v| [k.to_s, v]}
          }
        end

      end
    end
  end
end
