#
# Controller for Backups
#


module RCS
module DB

class PublicController < RESTController

  def index
    require_auth_level :tech

    mongoid_query do

      publics = ::PublicDocument.all

      return ok(publics)
    end
  end

  def destroy
    require_auth_level :tech
    
    mongoid_query do
      public = ::PublicDocument.find(@params['_id'])

      Frontend.collector_del(public[:name])
      Audit.log :actor => @session[:user][:name], :action => 'frontend.delete', :desc => "Deleted the file [#{public[:name]}] from the public folder"
      public.destroy

      return ok
    end
  end

end

end #DB::
end #RCS::