require 'addressable/uri'
require 'json'
require 'rest_client'
require 'crack/xml'
require 'awesome_print'

class Galavanting

	TRAVEL_MODES = %w(walking driving bicycling)
	COST_PER_SECOND = 10.0 / (60 * 60)
	DRIVING_COST_PER_M = 0.0001242742


	# def initialize
	# end

	def request(path, query_values, method)
		response = RestClient.get(path, { :params => query_values })

		if method == :json
			parse_json(response)
		else
			parse_xml(response)
		end
	end

	def parse_json(response)
	 	JSON.parse(response, :symbolize_names => true)
	end

	def parse_xml(response)
		Crack::XML.parse(response)
	end

	def float_to_dollars(float)
		"$" + sprintf("%05.2f", float)
	end

	def run
		puts "Welcome to GALAVANTING SAN FRANCISCO! We will calculate your cheapest route!!!?!?!?!"
		sleep 1
		printf "Please enter your starting location: "
		@start_location = gets.chomp
		printf "Please enter your end location: "
		@end_location = gets.chomp

		results = calculate_travel_costs

		puts "The cheapest mode of transportation is:"
		puts "#{results[0][:mode].capitalize}, which cost #{float_to_dollars(results[0][:cost])}"

		if results[0][:duration] && results[0][:distance]
			puts "It takes #{(results[0][:duration]/60).to_i} min., and is #{(results[0][:distance]/1000).to_i} km long."
		end

		puts ""
		puts "- - - - - - - -"
		puts ""

		results.each_with_index do |result, index|
			puts "#{index + 1}. #{result[:mode].capitalize} costs #{float_to_dollars(result[:cost])}"
		end


		# PP.pp(results)
	end

	def calculate_travel_costs
		results = []

		TRAVEL_MODES.each do |mode|

			result = request_directions(@start_location, @end_location, mode)

			if result[:status] == "OK"
				distance = result[:routes][0][:legs][0][:distance][:value]
				duration = result[:routes][0][:legs][0][:duration][:value]

				cost = duration * COST_PER_SECOND

				if mode == "driving"
					cost += distance * DRIVING_COST_PER_M
				end

				results << {:distance => distance, :duration => duration, :mode => mode, :cost => cost}
			end

		end


		cost_of_transit_variable = cost_of_transit

		if cost_of_transit_variable
			results << {:distance => nil, :duration => nil, :mode => "bart", :cost => cost_of_transit_variable}
		end

		results.sort_by! do |result|
			result[:cost]
		end

		results
	end

	def cost_of_transit
		start_station = find_nearest_station(@start_location)
		end_station = find_nearest_station(@end_location)

		start_walking = request_directions(@start_location, start_station[:location], "walking")
		end_walking = request_directions(@end_location, end_station[:location], "walking")


		start_walking_cost = start_walking[:routes][0][:legs][0][:duration][:value] * COST_PER_SECOND
		bart_cost = request_bart_cost(start_station[:abbr], end_station[:abbr])
		end_walking_cost = end_walking[:routes][0][:legs][0][:duration][:value] * COST_PER_SECOND

		puts ""
		puts "Walking to start station #{start_station[:abbr]} costs #{start_walking_cost}."
		puts "Walking to end station #{end_station[:abbr]} costs #{end_walking_cost}."
		puts ""

		if bart_cost["root"] && bart_cost["root"]["trip"]
			start_walking_cost.to_f + bart_cost["root"]["trip"]["fare"].to_f + end_walking_cost.to_f
		else
			nil
		end
	end

	def find_nearest_station(location)
		@bart_stations ||= request_bart_stations
		location_latlng = request_latlng(location)

		bart_stations_distance = []

		@bart_stations["root"]["stations"]["station"].each do |station|
			lat = station["gtfs_latitude"]
			lng = station["gtfs_longitude"]
			distance = calculate_latlng_distance(location_latlng, [lat, lng])
			abbr = station["abbr"]

			bart_stations_distance << {:abbr => abbr, :distance => distance, :lat => lat, :lng => lng, :location => "#{lat},#{lng}"}
		end

		bart_stations_distance.sort_by! do |station|
			station[:distance]
		end

		bart_stations_distance[0]
	end

	def calculate_latlng_distance(latlng1, latlng2)

		delta_x_sq = delta(latlng1[0], latlng2[0]) ** 2
		delta_y_sq = delta(latlng1[1], latlng2[1]) ** 2

		distance = (delta_x_sq + delta_y_sq) ** (1.0/2.0)
	end

	def delta(float1, float2)
		float1 = float1.to_f
		float2 = float2.to_f

		if float1 > float2
			float1 - float2
		else
			float2 - float1
		end
	end

	def request_bart_cost(start_station, end_station)
		query_values = {
			:cmd => 'fare',
			:orig => start_station,
			:dest => end_station,
			:key => 'MW9S-E7SL-26DU-VV8V'
		}

		request("http://api.bart.gov/api/sched.aspx", query_values, :xml)
	end

	def request_bart_stations
		query_values = {
			:cmd => 'stns',
			:key => 'MW9S-E7SL-26DU-VV8V'
		}

		request("http://api.bart.gov/api/stn.aspx", query_values, :xml)
	end

	def request_directions(start_location, end_location, travel_mode)
		query_values = {
			:origin => start_location,
			:destination => end_location,
			:mode => travel_mode,
			:sensor => 'false'
		}

		request("http://maps.googleapis.com/maps/api/directions/json", query_values, :json)
	end

	def request_latlng(location)
		query_values = {
			:address => location,
			:sensor => false,
			:region => 'us'
		}

		result = request("http://maps.googleapis.com/maps/api/geocode/json", query_values, :json)

		lat = result[:results][0][:geometry][:location][:lat]
		lng = result[:results][0][:geometry][:location][:lng]

		[lat, lng]
	end
end