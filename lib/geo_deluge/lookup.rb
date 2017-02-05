require 'JSON'
require_relative "mapzen_helpers.rb"

module GeoDeluge
  class Lookup
    include GeoDeluge::MapzenHelpers

    attr_reader :place_list, :cache

    def initialize(opts={})
      @place_list = {}
      @cache = opts[:cache_file] && File.exists?(opts[:cache_file]) ? JSON.parse(File.read(opts[:cache_file])) : {}
    end


    def get_name(id, opts={})
      if @cache[id].nil?
         get_canonical_form(id, opts)
      else
        @cache[id]["label"]
      end
    end

    def get_coordinates(id, opts={})
      if @cache[id].nil?
         get_lng_lat(id, opts)
      else
        [@cache[id]["lng"], @cache[id]["lat"]]
      end
    end

    def save_cache!(filename="./output/fast_cache.json")
      File.open(filename, "w+") { |file|  file.puts JSON.pretty_generate(cache)}
    end

    def get_line_geojson(data, opts={})
      place_lines = {
        type: "MultiLineString",
        coordinates: [] 
      }
      seen_lines = []
      data.each_with_index do |datum,i|
        place_points = []
        datum['places'].each do |place|
          place.each do |label, uri|
            place_points << get_coordinates(mapzen_id(uri))
          end
        end
        place_points.compact!
        if place_points.count > 1 && !(seen_lines.include?(place_points.hash))
          place_lines[:coordinates] << place_points 
          seen_lines << place_points.hash
        end
      end
      place_lines
    end

    def download_provenance_locations(datum, opts={})
      datum['places'].each do |place|
        place.each do |label, uri|
          place_id = mapzen_id(uri)
          if @cache[place_id].nil?
            puts "cache miss for #{place_id}"
            traverse_upwards(uri, opts)
            @cache.merge!(get_cache_representation(place_id))
          end
          @place_list[place_id] ||= {}
          @place_list[place_id][label] = @place_list[place_id][label].nil? ? 1 : @place_list[place_id][label] + 1
        end
      end
    end
  
    def validate_provenance_geography(datum, opts)
      error_text = ""
      datum['places'].each do |place|
        errors = []
        place.each do |label, uri|
          errors << "Missing URI for #{label}" if uri.empty?
          unless datum["provenance"].include?(label)
            errors << "Could not find #{label} in provenance text"
          end 
        end
        unless errors.empty?
          error_text << "Errors for #{datum["title"]} (#{datum["id"]}:\n--------------------------------\n"
          error_text <<  errors.join("\n")
          error_text << "\n\n"
        end
      end
      puts error_text if error_text.length > 0 && opts[:verbose]
      return error_text.empty?
    end

    ############################################################################
    protected
    ############################################################################

    def get_cache_representation(id, opts={})
      cache_item = {}
      cache_item["lng"], cache_item["lat"] = get_lng_lat(id, opts)  
      cache_item["label"] = get_canonical_form(id, opts)
      cache_item["country"] = get_country(id, opts)
      return {id => cache_item}
    end


  end
end