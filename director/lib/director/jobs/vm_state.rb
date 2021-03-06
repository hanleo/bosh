# Copyright (c) 2009-2012 VMware, Inc.

module Bosh::Director
  module Jobs
    class VmState < BaseJob
      TIMEOUT = 5

      @queue = :normal

      # @param [Integer] deployment_id Deployment id
      def initialize(deployment_id, format)
        @deployment_id = deployment_id
        @format = format
      end

      def perform
        vms = Models::Vm.filter(:deployment_id => @deployment_id)
        ThreadPool.new(:max_threads => Config.max_threads).wrap do |pool|
          vms.each do |vm|
            pool.process do
              vm_state = process_vm(vm)
              result_file.write(vm_state.to_json + "\n")
            end
          end
        end

        # task result
        nil
      end

      def process_vm(vm)
        ips = []
        job_name = nil
        job_state = nil
        resource_pool = nil
        job_vitals = nil
        index = nil

        begin
          agent = AgentClient.new(vm.agent_id, :timeout => TIMEOUT)
          agent_state = agent.get_state(@format)
          agent_state["networks"].each_value do |network|
            ips << network["ip"]
          end
          index = agent_state["index"]
          job_name = agent_state["job"]["name"] if agent_state["job"]
          job_state = agent_state["job_state"]
          if agent_state["resource_pool"]
            resource_pool = agent_state["resource_pool"]["name"]
          end
          if agent_state["vitals"]
            job_vitals = agent_state["vitals"]
          end
        rescue Bosh::Director::RpcTimeout
          job_state = "unresponsive agent"
        end

        instance = Models::Instance.find(deployment_id: @deployment_id, job: job_name, index: index)

        {
          :vm_cid => vm.cid,
          :ips => ips,
          :agent_id => vm.agent_id,
          :job_name => job_name,
          :index => index,
          :job_state => job_state,
          :resource_pool => resource_pool,
          :vitals => job_vitals,
          :resurrection_paused => instance ? instance.resurrection_paused  : nil,
        }
      end
    end
  end
end
