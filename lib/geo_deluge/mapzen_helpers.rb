require 'typhoeus'
require 'JSON'

module GeoDeluge
  module MapzenHelpers
    @@mapzen_content_cache = {}
    
    # 
    # Generate a mapzen ID number, given a mapzen URI.
    # @param uri [String] the URI to generate from
    # 
    # @return [String] a Mapzen ID, or "unknown" if the URI cannot be parsed.
    def mapzen_id(uri)
      uri.split("/")&.last&.split(".")&.first || "unknown" 
    end 

    # 
    # Generate a Mapzen URI, given a mapzen ID number
    # @param id [String] The id of a Mapzen location
    # 
    # @return [String] A URI for a mapzen location
    def mapzen_url(id)
      return nil if id=="unknown" || id.nil?
      id = id.to_s
      parts = []
      while id
        parts << id[0..2]
        id = id[3..-1]
      end
      "https://whosonfirst.mapzen.com/data/#{parts.join("/")}/#{parts.join("")}.geojson"
    end

    def traverse_upwards(uri, opts = {}) 
      json = download_geojson(uri, opts)
      return false unless json 
      parent = json.dig("properties", "wof:parent_id")
      return true if parent == -1 || parent.nil?
      traverse_upwards(mapzen_url(parent), opts)
    end

    def get_lng_lat(id, opts= {}) 
      data = download_geojson(mapzen_url(id),opts)
      return [nil, nil] unless data
      lat = data.dig("properties","geom:latitude")
      lng = data.dig("properties","geom:longitude")
      if lat.nil? || lng.nil?
        # lat = data.dig("properties","lbl:latitude")
        # lng = data.dig("properties","lbl:longitude")
        puts "#{id} is missing geo coordinates." if opts[:verbose]
      end   
      [lng, lat]
    end

    # Look for the geographical hierarchy, and bail out if it's missing.
    def get_hierarchy(id, opts) 
      data = download_geojson(mapzen_url(id),opts)
      return nil if data.nil?
      hierarchy = data.dig("properties","wof:hierarchy").first
      if hierarchy.nil? || hierarchy.empty?
        puts "no hierarchy for #{id}" if opts[:verbose]
        return nil 
      end
      return hierarchy
    end

    def get_country(id, opts={})
      data = download_geojson(mapzen_url(id),opts)
      return nil if data.nil?
      hierarchy = get_hierarchy(id, opts)
      if hierarchy.nil? || hierarchy["country_id"].nil?
        puts "no country hierarchy for #{id}" if opts[:verbose] 
        return nil 
      end

      # Get the country, and bail out if it's missing.
      country = download_geojson(mapzen_url(hierarchy["country_id"]), opts)
      if country.nil?
        puts "could not find a country for #{place_name} (id: #{id})" if opts[:verbose]
        return nil
      end
      get_preferred_name(country)
    end

    def get_state_abbreviation(id, opts={})
      data = opts[:data] || download_geojson(mapzen_url(id),opts)

      hierarchy = get_hierarchy(id, opts)
      if hierarchy.nil? || hierarchy["region_id"].nil?
        puts "no state hierarchy for #{id}" if opts[:verbose] 
        return nil 
      end

      # Get the country, and bail out if it's missing.
      state = download_geojson(mapzen_url(hierarchy.dig("region_id")), opts)
      if state.nil?
        puts "cannot find a state for #{place_name} (id: #{id})" if opts[:verbose]
        return nil
      end
      return state.dig("properties", "wof:abbreviation")
    end


    # Get the name of the place.  Prefers english, but'll take the default.
    def get_preferred_name(data)
      if preferred_english_names = data.dig("properties", "name:eng_x_preferred")
        preferred_english_names.first
      else
        data.dig("properties", "wof:name")
      end
    end

    def get_canonical_form(id, opts = {})
      data = download_geojson(mapzen_url(id),opts)
      if data.nil?
        puts "could not get canonical form for #{id}" if opts[:verbose]
        return nil
      end

      place_name = get_preferred_name(data)

      # If it's a country or continent, return the name. 
      if ["country", "continent"].include? data.dig("properties", "wof:placetype")
        return place_name
      end

      country_name = get_country(id)
      if country_name.nil?
        return place_name
      end

      # If it's a US place, and it's not a state, then do "name, state".  
      # otherwise, do "Place, country."
      #
      # If there's not a state associated with a US place,
      # bail out with just the place name.
      if country_name == "United States" && data.dig("properties", "wof:placetype") != "region"  
        if state_abbr = get_state_abbreviation(id)
          return "#{place_name}, #{state_abbr}"
        else
          return place_name
        end
      else
        [place_name, country_name].compact.join(", ")
      end
    end

    # 
    # Download a geojson file from Mapzen.  This will first scan
    # @param uri [String] the URI to download
    # @param opts [Hash] Options for download.
    #
    # @option opts [Boolean] :force (false) re-download the file even if it exists
    # @option opts [Number]  :sleep (0.05) the amount of time to sleep between downloads
    # @option opts [String]  :output_dir ("caches/mapzen") the directory in whichto save downloaded files
    # @option opts [Boolean] :verbose (false) Output debugging messages to the console
    # 
    # @return [Hash, Nil] the parsed file if the download was successful, Nil otherwise.
    def download_geojson(uri, opts = {})
      return nil if uri.nil? || uri.empty?
      return @@mapzen_content_cache[uri] if @@mapzen_content_cache[uri]

      force         = opts.fetch(:force, false)
      sleep_duration = opts.fetch(:sleep, 0.05)
      output_dir    = opts.fetch(:output_dir, "caches/mapzen")
      verbose       = opts.fetch(:verbose, false)

      id = mapzen_id(uri)
      path = "#{output_dir}/#{id}.geojson"
      return JSON.parse(File.read(path)) if (File.exist?(path) && !force)
      puts "downloading #{uri}" if verbose
      content =Typhoeus.get(uri, followlocation: true).body
      begin
        json = JSON.parse(content) 
      rescue JSON::ParserError => e 
        puts "Invalid JSON at #{uri}: #{e}" if verbose
        return nil
      end
      begin
        File.open(path, "w") { |io|  io.puts content}
      rescue => e
        puts "Error writing #{uri}: #{e}" if verbose
        return nil
      end
      @@mapzen_content_cache[uri] = json
      sleep(sleep_duration)
      return json
    end
  end
end