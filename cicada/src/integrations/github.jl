"""
GitHub integration for key deployment
"""

using HTTP
using JSON3
using UUIDs

include("../keygen/types.jl")
include("../storage/keystore.jl")
include("../utils/errors.jl")
include("../utils/logging.jl")

"""
Upload SSH key to GitHub
"""
function upload_to_github(
    key_id::UUID,
    key_dir::String,
    github_token::String;
    title::Union{String, Nothing}=nothing
)::Dict{String, Any}
    try
        log_key_operation("GITHUB_UPLOAD", "Uploading key $key_id to GitHub")

        # Load key
        keys = list_keys(key_dir)
        found = false
        public_key_content = ""

        for stored_key in keys
            if stored_key.id == key_id
                found = true
                public_key_content = read(stored_key.public_key_path, String)
                break
            end
        end

        if !found
            throw(IntegrationError("Key not found: $key_id"))
        end

        # Generate title if not provided
        if isnothing(title)
            title = "CIcaDA-$(string(key_id)[1:8])"
        end

        # Prepare request
        url = "https://api.github.com/user/keys"
        headers = [
            "Authorization" => "token $github_token",
            "Accept" => "application/vnd.github.v3+json",
            "User-Agent" => "CIcaDA-KeyManager"
        ]

        body = Dict(
            "title" => title,
            "key" => strip(public_key_content)
        )

        # Upload to GitHub
        response = HTTP.post(
            url,
            headers,
            JSON3.write(body)
        )

        if response.status == 201
            result = JSON3.read(String(response.body))

            log_key_operation("GITHUB_UPLOAD", "Key uploaded successfully: ID=$(result.id)")

            return Dict{String, Any}(
                "success" => true,
                "github_key_id" => result.id,
                "title" => result.title,
                "created_at" => result.created_at
            )
        else
            throw(IntegrationError("GitHub API returned status $(response.status)"))
        end
    catch e
        if e isa HTTP.Exceptions.StatusError
            error_body = String(e.response.body)
            throw(IntegrationError("GitHub API error: $error_body"))
        else
            throw(IntegrationError("Failed to upload to GitHub: $(e)"))
        end
    end
end

"""
List SSH keys from GitHub
"""
function list_github_keys(github_token::String)::Vector{Dict{String, Any}}
    try
        url = "https://api.github.com/user/keys"
        headers = [
            "Authorization" => "token $github_token",
            "Accept" => "application/vnd.github.v3+json",
            "User-Agent" => "CIcaDA-KeyManager"
        ]

        response = HTTP.get(url, headers)

        if response.status == 200
            keys = JSON3.read(String(response.body))

            return [Dict{String, Any}(
                "id" => k.id,
                "title" => k.title,
                "key" => k.key,
                "created_at" => k.created_at
            ) for k in keys]
        else
            throw(IntegrationError("GitHub API returned status $(response.status)"))
        end
    catch e
        if e isa HTTP.Exceptions.StatusError
            error_body = String(e.response.body)
            throw(IntegrationError("GitHub API error: $error_body"))
        else
            throw(IntegrationError("Failed to list GitHub keys: $(e)"))
        end
    end
end

"""
Delete SSH key from GitHub
"""
function delete_from_github(github_token::String, github_key_id::Int)::Bool
    try
        log_key_operation("GITHUB_DELETE", "Deleting key $github_key_id from GitHub")

        url = "https://api.github.com/user/keys/$github_key_id"
        headers = [
            "Authorization" => "token $github_token",
            "Accept" => "application/vnd.github.v3+json",
            "User-Agent" => "CIcaDA-KeyManager"
        ]

        response = HTTP.delete(url, headers)

        if response.status == 204
            log_key_operation("GITHUB_DELETE", "Key deleted successfully")
            return true
        else
            throw(IntegrationError("GitHub API returned status $(response.status)"))
        end
    catch e
        if e isa HTTP.Exceptions.StatusError
            error_body = String(e.response.body)
            throw(IntegrationError("GitHub API error: $error_body"))
        else
            throw(IntegrationError("Failed to delete from GitHub: $(e)"))
        end
    end
end

"""
Verify GitHub token validity
"""
function verify_github_token(github_token::String)::Bool
    try
        url = "https://api.github.com/user"
        headers = [
            "Authorization" => "token $github_token",
            "Accept" => "application/vnd.github.v3+json",
            "User-Agent" => "CIcaDA-KeyManager"
        ]

        response = HTTP.get(url, headers)

        return response.status == 200
    catch e
        return false
    end
end
