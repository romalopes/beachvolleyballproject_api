Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # origins(
    #   "https://beachvolleyballproject.vercel.app",
    #   "http://localhost:5174,
    #   http://localhost:3001"
    # )
    origins "*"
    # origins ENV.fetch("FRONTEND_URL")
    # if Rails.env.development?
      # allowed_origins << "http://localhost:5173"
    # end


    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end



# allowed_origins = [
#   "https://beachvolleyballproject.vercel.app"
# ]

# if Rails.env.development?
#   allowed_origins << "http://localhost:5174"
# end

# Rails.application.config.middleware.insert_before 0, Rack::Cors do
#   allow do
#     origins(*allowed_origins)

#     resource "*",
#       headers: :any,
#       methods: [:get, :post, :put, :patch, :delete, :options, :head]
#   end
# end