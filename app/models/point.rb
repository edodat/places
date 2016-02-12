class Point
  attr_accessor :latitude, :longitude

  def initialize params
     @latitude = params[:lat] ? params[:lat] : params[:coordinates][1]
     @longitude = params[:lng] ? params[:lng] : params[:coordinates][0]
  end

  def to_hash
    return { type:"Point", coordinates:[ @longitude, @latitude ]}
  end

end
