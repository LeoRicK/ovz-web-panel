ActionController::Routing::Routes.draw do |map|
  # The priority is based upon order of creation: first created -> highest priority.
  
  map.logout '/logout', :controller => 'sessions', :action => 'destroy'
  map.login '/login', :controller => 'sessions', :action => 'new'
  
  map.resource :session
  
  map.namespace :admin do |admin|
    admin.dashboard '/dashboard', :controller => 'dashboard'
    admin.connect '/users/:action', :controller => 'users'
    admin.connect '/hardware-servers/:action', :controller => 'hardware_servers'
  end

  map.root :controller => 'sessions', :action => 'new'

  #map.connect ':controller/:action/:id'
  #map.connect ':controller/:action/:id.:format'
end
