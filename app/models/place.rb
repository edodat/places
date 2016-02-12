class Place
  attr_accessor :id, :formatted_address, :location, :address_components

  def self.mongo_client
    Mongoid::Clients.default
  end

  def self.collection
    self.mongo_client[:places]
  end

  def self.load_all file
    documents = JSON.parse(file.read)
    self.collection.insert_many documents
  end

  def self.to_places view
    places = []
    view.each do |place|
      places << Place.new(place)
    end
    return places
  end

  def initialize params
    @id = params[:_id].to_s
    @formatted_address = params[:formatted_address]
    @location = Point.new(params[:geometry][:geolocation])
    @address_components = []
    params[:address_components].each do |address_component|
      @address_components << AddressComponent.new(address_component)
    end unless params[:address_components].nil?
  end

  def self.find_by_short_name short_name
    self.collection.find("address_components.short_name": short_name)
  end

  def self.find id
    place = self.collection.find(_id: BSON::ObjectId.from_string(id)).first
    return place.nil? ? nil : Place.new(place)
  end

  def self.all(offset=0, limit=nil)
    result = self.collection.find.skip(offset)
    result = result.limit(limit) unless limit.nil?
    self.to_places(result)
  end

  def destroy
    self.class.collection.find(_id: BSON::ObjectId.from_string(@id)).delete_one
  end

  def self.get_address_components(sort=nil, offset=nil, limit=nil)
    pipeline = [
        { "$unwind": "$address_components" },
        { "$project": {
          address_components: "$address_components",
          formatted_address: "$formatted_address",
          "geometry.geolocation": "$geometry.geolocation"
          }
        }
    ]
    pipeline << { "$sort": sort } unless sort.nil?
    pipeline << { "$skip": offset } unless offset.nil?
    pipeline << { "$limit": limit } unless limit.nil?

    self.collection.find.aggregate(pipeline)
  end

  def self.get_country_names
    self.collection.find.aggregate([
      { "$unwind": "$address_components" },
      { "$project": { long_name: "$address_components.long_name", types: "$address_components.types" }},
      { "$unwind": "$types" },
      { "$match": { types: "country" }},
      { "$group": { _id: "$long_name" }}
    ]).to_a.map {|doc| doc[:_id]}
  end

  def self.create_indexes
    self.collection.indexes.create_one("geometry.geolocation": Mongo::Index::GEO2DSPHERE)
  end

  def self.remove_indexes
    self.collection.indexes.drop_one("geometry.geolocation_2dsphere")
  end

  def self.near(point, max_meters=nil)
    near = { "$geometry": point.to_hash }
    near[:$maxDistance] = max_meters unless max_meters.nil?
    self.collection.find("geometry.geolocation": { "$near": near })
  end

  def near(max_meters=nil)
    self.class.to_places(self.class.near(@location, max_meters))
  end
end
