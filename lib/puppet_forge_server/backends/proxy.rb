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
require 'digest/sha1'

module PuppetForgeServer::Backends
  class Proxy

    def initialize(url, cache_dir, http_client, file_path)
      @url = url
      @cache_dir = File.join(cache_dir, Digest::SHA1.hexdigest(@url))
      @http_client = http_client
      @log = PuppetForgeServer::Logger.get
      @file_path = file_path

      # Create directory structure for all alphabetic letters
      (10...36).each do |i|
        FileUtils.mkdir_p(File.join(@cache_dir, i.to_s(36)))
      end
    end

    def get_file_buffer(relative_path)
      @log.debug "Get file buffer: #{relative_path}"
      file_name = relative_path.split('/').last
      @log.debug "File name: #{file_name}"
      File.join(@cache_dir, file_name[0].downcase, file_name)
      path = Dir["#{@cache_dir}/**/#{file_name}"].first
      unless File.exist?("#{path}")
        buffer = download("#{@file_path.chomp('/')}/#{relative_path}")
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

    def upload(file_data)
      @log.debug 'File upload is not supported by the proxy backends'
      false
    end

    protected
    attr_reader :log

    def get(relative_url)
      @log.debug "relative_url: #{relative_url}"
      full_url=url(relative_url)
      @log.debug "full_url:#{full_url}"
      @http_client.get(full_url)
    end

    def download(relative_url)
      @log.debug "download relative_url: #{relative_url}"
      full_url=url(relative_url)
      @log.debug "download full_url:#{full_url}"
      @http_client.download(url(relative_url))
    end

    def url(relative_url)
      @url + relative_url
    end
  end
end
