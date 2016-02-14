class Photo
  attr_accessor :id, :location, :place
  attr_writer :contents

  def self.mongo_client
    Mongoid::Clients.default
  end

  def self.collection
    self.mongo_client.database.fs
  end

  def self.to_photos view
    photos = []
    view.each do |photo|
      photos << Photo.new(photo)
    end
    return photos
  end

  def initialize params={}
    @id = params[:_id].to_s unless params[:_id].nil?
    if params[:metadata] && params[:metadata][:location]
      @location = Point.new(params[:metadata][:location])
    end
    if params[:metadata] && params[:metadata][:place]
      @place = params[:metadata][:place]
    end
  end

  def place
    return @place.nil? ? nil : Place.find(@place.to_s)
  end

  def place= object
    @place = object
    @place = BSON::ObjectId.from_string(object) if object.is_a? String
    @place = BSON::ObjectId.from_string(object.id) if object.respond_to? :id
  end

  def persisted?
    not @id.nil?
  end

  def save
    if !persisted?
      # extract location info
      gps=EXIFR::JPEG.new(@contents).gps
      @contents.rewind
      @location = Point.new(lat: gps[:latitude], lng: gps[:longitude])
      metadata = gps.nil? ? {} : { location: @location.to_hash }
      metadata[:place] = @place

      file = Mongo::Grid::File.new(@contents.read, content_type: "image/jpeg", metadata: metadata)
      id = self.class.collection.insert_one(file)
      @id = id.to_s
    else
      modifier = {}
      modifier['metadata.location'] = @location.to_hash unless @location.nil?
      modifier['metadata.place'] = @place unless @place.nil?
      self.class.collection.find(_id: BSON::ObjectId.from_string(@id)).update_one("$set": modifier)
    end
  end

  def self.all(offset=0, limit=nil)
    result = self.collection.find.skip(offset)
    result = result.limit(limit) unless limit.nil?
    self.to_photos(result)
  end

  def self.find id
    photo = self.collection.find(_id: BSON::ObjectId.from_string(id)).first
    return photo.nil? ? nil : Photo.new(photo)
  end

  def contents
    photo = self.class.collection.find_one(_id: BSON::ObjectId.from_string(@id))
    if photo
      buffer = ""
      photo.chunks.reduce([]) do |x,chunk|
        buffer << chunk.data.data
      end
      return buffer
    end
  end

  def find_nearest_place_id max_meters
    place = Place.near(@location, max_meters).limit(1).projection(_id:1).first
    return place.nil? ? 0 : place[:_id]
  end

  def self.find_photos_for_place id
    self.collection.find("metadata.place": BSON::ObjectId.from_string(id.to_s))
  end

  def destroy
    self.class.collection.find(_id: BSON::ObjectId.from_string(@id)).delete_one
  end
end
