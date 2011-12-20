require_relative '../grid'

module RCS
module DB

class FileController < RESTController
  
  def show
    require_auth_level :admin, :sys, :tech, :view
    
    file_name = @params['_id']
    file_path = Config.instance.temp(file_name)
    
    not_found unless File.exists? file_path
    stream_file(file_path)
    #stream_file('cores/offline.zip')
  end
  
  def destroy
    require_auth_level :none
    
    file_name = @params['_id']
    file_path = Config.instance.temp(file_name)
    File.unlink file_path
    
    ok
  end
  
end

end # ::DB
end # ::RCS