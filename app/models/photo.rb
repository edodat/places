class Photo
  attr_accessor :id, :location
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

      file = Mongo::Grid::File.new(@contents.read, content_type: "image/jpeg", metadata: metadata)
      id = self.class.collection.insert_one(file)
      @id = id.to_s
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

  def destroy
    self.class.collection.find(_id: BSON::ObjectId.from_string(@id)).delete_one
  end
end
