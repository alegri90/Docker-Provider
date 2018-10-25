#!/usr/local/bin/ruby
# frozen_string_literal: true

module Fluent
    
      class Kube_Services_Input < Input
        Plugin.register_input('kubeservices', self)
    
        def initialize
          super
          require 'yaml'
          require 'json'
    
          require_relative 'KubernetesApiClient'
          require_relative 'oms_common'
          require_relative 'omslog'
        end
    
        config_param :run_interval, :time, :default => '1m'
        config_param :tag, :string, :default => "oms.api.KubeServices.CollectionTime"
    
        def configure (conf)
          super
        end
    
        def start
          if @run_interval
            @finished = false
            @condition = ConditionVariable.new
            @mutex = Mutex.new
            @thread = Thread.new(&method(:run_periodic))
          end
        end
    
        def shutdown
          if @run_interval
            @mutex.synchronize {
              @finished = true
              @condition.signal
            }
            @thread.join
          end
        end
    
        def enumerate
            currentTime = Time.now
            emitTime = currentTime.to_f
            batchTime = currentTime.utc.iso8601
              $log.info("in_kube_services::enumerate : Getting services from Kube API @ #{Time.now.utc.iso8601}")
              serviceList = JSON.parse(KubernetesApiClient.getKubeResourceInfo('services').body)
              $log.info("in_kube_services::enumerate : Done getting services from Kube API @ #{Time.now.utc.iso8601}")
              begin
                if(!serviceList.empty?)
                  eventStream = MultiEventStream.new
                  serviceList['items'].each do |items|
                    record = {}
                    record['CollectionTime'] = batchTime #This is the time that is mapped to become TimeGenerated
                    record['ServiceName'] = items['metadata']['name']
                    record['Namespace'] = items['metadata']['namespace']
                    record['SelectorLabels'] = [items['spec']['selector']]
                    record['ClusterId'] = KubernetesApiClient.getClusterId
                    record['ClusterName'] = KubernetesApiClient.getClusterName
                    record['ClusterIP'] = items['spec']['clusterIP']
                    record['ServiceType'] = items['spec']['type']
                    #<TODO> : Add ports and status fields
                    eventStream.add(emitTime, record) if record   
                  end
                  router.emit_stream(@tag, eventStream) if eventStream
                end  
              rescue  => errorStr
                $log.warn line.dump, error: errorStr.to_s
                $log.debug_backtrace(e.backtrace)
              end   
        end
    
        def run_periodic
          @mutex.lock
          done = @finished
          until done
            @condition.wait(@mutex, @run_interval)
            done = @finished
            @mutex.unlock
            if !done
              begin
                $log.info("in_kube_services::run_periodic @ #{Time.now.utc.iso8601}")
                enumerate
              rescue => errorStr
                $log.warn "in_kube_services::run_periodic: enumerate Failed to kube services: #{errorStr}"
              end
            end
            @mutex.lock
          end
          @mutex.unlock
        end
    
      end # Kube_Services_Input
    
    end # module
    
    