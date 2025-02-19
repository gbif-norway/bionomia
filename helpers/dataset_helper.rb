# encoding: utf-8

module Sinatra
  module Bionomia
    module Helper
      module DatasetHelper

        def dataset_from_param
          @dataset = Dataset.find_by_datasetKey(params[:id]) rescue nil
          if @dataset.nil?
            halt 404
          end
        end

        def search_dataset
          searched_term = params[:q] || params[:dataset]
          @results = []
          return if !searched_term.present?

          page = (params[:page] || 1).to_i

          client = Elasticsearch::Client.new(
            url: Settings.elastic.server,
            request_timeout: 5*60,
            retry_on_failure: true,
            reload_on_failure: true,
            reload_connections: 1_000,
            adapter: :typhoeus
          )
          body = build_dataset_query(searched_term)
          from = (page -1) * 30

          response = client.search index: Settings.elastic.dataset_index, from: from, size: 30, body: body
          results = response["hits"].deep_symbolize_keys

          @pagy = Pagy.new(count: results[:total][:value], items: 30, page: page)
          @results = results[:hits]
        end

        def datasets
          if params[:order] && Dataset.column_names.include?(params[:order]) && ["asc", "desc"].include?(params[:sort])
            data = Dataset.order("#{params[:order]} #{params[:sort]}")
          elsif params[:has_identifiers] && params[:has_identifiers] == "true"
            data = Dataset.where.not(source_attribution_count: 0).order(:title)
          else
            data = Dataset.order(:title)
          end
          begin
            @pagy, @results = pagy(data)
          rescue Pagy::OverflowError
            halt 404
          end
        end

        def dataset_users
          begin
            if @dataset.is_large?
              @pagy, @results = pagy_countless(@dataset.users.order(:family))
            else
              @pagy, @results = pagy(@dataset.users.order(:family))
            end
          rescue Pagy::OverflowError
            halt 404
          end
        end

        def dataset_agents
          begin
            @pagy, @results = pagy_array(@dataset.agents.to_a, items: 75)
          rescue Pagy::OverflowError
            halt 404
          end
        end

        def dataset_agents_counts
          begin
            @pagy, @results = pagy_array(@dataset.agents_occurrence_counts.to_a, items: 75)
          rescue Pagy::OverflowError
            halt 404
          end
        end

        def dataset_agents_unclaimed_counts
          begin
            @pagy, @results = pagy_array(@dataset.agents_occurrence_unclaimed_counts.to_a, items: 75)
          rescue Pagy::OverflowError
            halt 404
          end
        end

        def dataset_stats
          dataset_from_param
          {
            title: "#{@dataset.title}",
            description: "#{@dataset.description}",
            datasetKey: "#{@dataset.datasetKey}",
            doi: "#{@dataset.doi}",
            license: "#{@dataset.license}",
            people: @dataset.users_count
          }
        end

        def dataset_scribes
          begin
            @pagy, @results = pagy(@dataset.scribes.order(:family))
          rescue Pagy::OverflowError
            halt 404
          end
        end

        def dataset_json_ld
          descriptor = {
            "@context": "http://schema.org",
            "@type": "Dataset",
            "@id": "https://doi.org/#{@dataset.doi}",
            identifier: [
              {
                "@type": "PropertyValue",
                propertyID: "doi",
                value: "https://doi.org/#{@dataset.doi}"
              },
              {
                "@type": "PropertyValue",
                propertyID: "UUID",
                value: "#{@dataset.datasetKey}"
              }
            ],
            url: "https://bionomia.net/dataset/#{@dataset.datasetKey}/datapackage.json",
            name: "ATTRIBUTIONS MADE FOR: #{h(@dataset.title)}"
          }
          if @dataset.description
            descriptor.merge!(
              {
                description: "#{h(Sanitize.fragment(@dataset.description))}"
              }
            )
          else
            descriptor.merge!(
              {
                description: "(The description of this dataset is missing or too short)"
              }
            )
          end
          if @dataset.license && @dataset.license_icon
            descriptor.merge!(
              {
                license: "#{@dataset.license}"
              }
            )
          end
          if @dataset.image_url
            descriptor.merge!(
              {
                image: "https://abekpgaoen.cloudimg.io/bound/350x200/q100/#{@dataset.image_url}"
              }
            )
          end
          if @compressed_file_size
            descriptor.merge!(
              {
                distribution: {
                  contentUrl: "https://bionomia.net/dataset/#{@dataset.datasetKey}/datapackage.json",
                  contentSize: "#{@compressed_file_size} MB",
                  encodingFormat: "https://frictionlessdata.io/specs/"
                }
              }
            )
          end
          descriptor
        end

      end
    end
  end
end
