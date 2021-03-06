# -*- encoding: utf-8 -*-
#
# Copyright 2014 North Development AB
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'json'
require 'digest/md5'
require 'uri'
require 'lru_redux'

module PuppetForgeServer::Backends
  class ProxyPulp < PuppetForgeServer::Backends::Proxy

    # Priority should be lower than v3 API proxies as v3 requires less API calls
    @@PRIORITY = 14
    @@FILE_PATH = '/pulp/puppet'
    attr_reader :PRIORITY

    def initialize(url, cache_dir, metadata_ttl, http_client = PuppetForgeServer::Http::HttpClient.new)
      super(url, cache_dir, http_client, @@FILE_PATH)
      @forge_id = URI(@url).path.split('/').last
      uri=URI.parse(@url)
      @forge_host="http://#{uri.host}:#{uri.port}"
      @forge_repo_dir="#{@forge_host}#{@@FILE_PATH}/#{@forge_id}"
      #a cache size 2 and ttl
      real_ttl = metadata_ttl || 10
      @log.debug "metadata_ttl set to #{real_ttl} secs"
      @modules_json_cache = LruRedux::TTL::ThreadSafeCache.new(2, metadata_ttl||10)
    end

    def get_file_buffer(relative_path)
      #the file path returned by pulp include /pulp/puppet portion
      relative_path=relative_path.gsub(/^#{@@FILE_PATH}/, '')
      @log.debug "Get file buffer: #{relative_path}"
      file_name = relative_path.split('/').last
      @log.debug "File name: #{file_name}"
      File.join(@cache_dir, file_name[0].downcase, file_name)
      path = Dir["#{@cache_dir}/**/#{file_name}"].first
      unless File.exist?("#{path}")
        buffer = download_module("#{@file_path.chomp('/')}/#{relative_path}")
        File.open(File.join(@cache_dir, file_name[0].downcase, file_name), 'wb') do |file|
          file.write(buffer.read)
        end
        path = File.join(@cache_dir, file_name[0].downcase, file_name)
      end
      File.open(path, 'rb')
    rescue => e
      @log.error("#{self.class.name} failed downloading file '#{relative_path}'")
      @log.error("Error: #{e}")
      return nil
    end


    def get_metadata(author, name, options = {})
      options = ({:with_checksum => true}).merge(options)
      query ="#{author}/#{name}"
      version = options[:version]
      begin
        query_modules=get_module_json(query)
        @log.debug "!!!!get_metatdata Query modules: #{query_modules} with query: #{query} with version: #{version}"
        #now find version match
        if version && query_modules.length>0
          #@log.debug "query_modules class is #{query_modules.class}"
          matched_modules = query_modules.select {|current| current['version']==version}
          @log.debug "matched_modules : #{matched_modules.to_s}"
        else
          matched_modules = query_modules
        end

        #get_modules(query_modules, options)
        get_modules(matched_modules, options)
      rescue => e
        @log.debug("#{self.class.name} failed getting metadata for '#{query}' with options #{options}")
        @log.debug("Error: #{e}")
        return nil
      end
    end

    def query_metadata(query, options = {})
      options = ({:with_checksum => true}).merge(options)
      begin
        query_modules=get_module_json(query)
        @log.debug "Query modules: #{query_modules} with query: #{query}"
        modules_found=get_modules(query_modules, options)
        @log.debug "Modules found total #{modules_found.length}: #{modules_found.to_s}"
        return modules_found
      rescue => e
        @log.debug("#{self.class.name} failed querying metadata for '#{query}' with options #{options}")
        @log.debug("Error: #{e}")
        return nil
      end
    end

    private
    def read_metadata(element, release)
      # bug is here
      element['project_page'] = element['project_url']
      element['name']=element['full_name'] ? element['full_name'].gsub('/', '-') : "#{element['author']}-#{element['name']}"
      element['description'] = element['desc']
      element['version'] = release['version'] ? release['version'] : element['version']
      element['dependencies'] = release['dependencies'] ? release['dependencies'] : []
      %w(project_url full_name releases tag_list desc).each { |key| element.delete(key) }
      element
    end

    def parse_dependencies(metadata)
      metadata.dependencies = metadata.dependencies.dup.map do |dependency|
        PuppetForgeServer::Models::Dependency.new({:name => dependency[0], :version_requirement => dependency.length > 1 ? dependency[1] : nil})
      end.flatten
      metadata
    end

    def get_modules(modules, options)
      loop_count=0
      modules.map do |element|
        version = options['version'] ? "&version=#{options['version']}" : ''
        metadata_url = "/api/v1/releases.json?module=#{element['author']}/#{element['name']}&version=#{element['version']}"
        @log.debug "metadata_url : #{metadata_url}"
        @log.debug "get_modules element: #{element.to_s}"
        returned_metadata=get(metadata_url)
        loop_count=loop_count+1
        @log.debug "returned_metadata with class #{returned_metadata.class}: #{returned_metadata} in loop #{loop_count}"
        parsed_return = JSON.parse(returned_metadata)
        real_metadata = parsed_return["#{element['author']}/#{element['name']}"].last # it is an array
        @log.debug "real metadata : #{real_metadata.to_s}"
        tags = element['tag_list'] ? element['tag_list'] : nil

        # JSON.parse(returned_metadata).values.last.map do |release|
        #   @log.debug "release"
        #   tags = element['tag_list'] ? element['tag_list'] : nil
        #   raw_metadata = read_metadata(element, release)
        #   @log.debug "raw_metadata: #{raw_metadata.to_s}"
        #   PuppetForgeServer::Models::Module.new({
        #     :metadata => parse_dependencies(PuppetForgeServer::Models::Metadata.new(raw_metadata)),
        #     :checksum => options[:with_checksum] ? Digest::MD5.hexdigest(File.read(get_file_buffer(release['file']))) : nil,
        #     :path => "#{release['file']}".gsub(/^#{@@FILE_PATH}/, ''),
        #     :tags => tags,
        #     :private => true
        #   })
        # end
        release = real_metadata
        raw_metadata = read_metadata(element, release)
        @log.debug "raw_metadata: #{raw_metadata.to_s}"
        PuppetForgeServer::Models::Module.new({
          :metadata => parse_dependencies(PuppetForgeServer::Models::Metadata.new(raw_metadata)),
          :checksum => options[:with_checksum] ? Digest::MD5.hexdigest(File.read(get_file_buffer(release['file']))) : nil,
          :path => "#{release['file']}".gsub(/^#{@@FILE_PATH}/, ''),
          :tags => tags,
          :private => true
        })
      end
    end

    def get_module_json(query)
      json_uri="#{@forge_repo_dir}/modules.json"
      @log.debug "JSON_URI: #{json_uri}"
      raw_json=@modules_json_cache[:modules_json]
      unless raw_json
       @log.debug "cache miss, requesting modules json"
       raw_json = @http_client.get(json_uri)
       @modules_json_cache[:modules_json] = raw_json
      end
      #need cache the raw json from pulp
      @log.debug "Raw json: #{raw_json}"
      json_filtered=JSON.parse(raw_json).select { |e|  "#{e['author']}/#{e['name']}".match("#{query}") }
    end

    def download_module(relative_url)
      @log.debug "download module relative_url: #{relative_url} from #{@forge_host} with file_path #{@file_path}"
      full_url="#{@forge_host}/#{relative_url}"
      @log.debug "download module full_url:#{full_url}"
      @http_client.download(full_url)
    end

  end
end
