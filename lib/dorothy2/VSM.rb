# Copyright (C) 2010-2013 marco riccardi.
# This file is part of Dorothy - http://www.honeynet.it/
# See the file 'LICENSE' for copying permission.

module Dorothy

  #Dorothy module-class for managig the virtual sandboxes
  class Doro_VSM
    #ESX vSphere5 interface
    class ESX

      #Creates a new instance for communicating with ESX through the vSpere5's API
      def initialize(server,user,pass,vmname,guestuser,guestpass)

        begin
          vim = RbVmomi::VIM.connect(:host => server , :user => user, :password=> pass, :insecure => true)
        rescue Timeout::Error
          raise "Fail to connect to the ESXi server #{server} - TimeOut (Are you sure that is the right address?)"
        end

        @server = server
        dc = vim.serviceInstance.find_datacenter
        @vm = dc.find_vm(vmname)

        raise "Virtual Machine #{vmname} not present within ESX!!" if @vm.nil?

        om = vim.serviceContent.guestOperationsManager
        am = om.authManager
        @pm = om.processManager
        @fm = om.fileManager

        #AUTHENTICATION
        guestauth = {:interactiveSession => false, :username => guestuser, :password => guestpass}
        r = 0
        begin
          @auth=RbVmomi::VIM::NamePasswordAuthentication(guestauth)
          abort if am.ValidateCredentialsInGuest(:vm => @vm, :auth => @auth) != nil
        rescue RbVmomi::Fault => e
          if e.inspect =~ /InvalidPowerState/
            if r <= 5
              r = r+1
              LOGGER.debug "VSM", "VM busy (maybe still revertig, retrying.."
              sleep 2
              retry
            end
            LOGGER.error "VSM", "Error, can't connect to VM #{@vm[:name]}"
            LOGGER.debug "VSM", e
            raise "VSM Error"
          end
        end

      end

      def revert_vm
        @vm.RevertToCurrentSnapshot_Task
      end

  def find_node(tree, name)
    snapshot = nil
    tree.each do |node|
      if node.name == name
        snapshot = node.snapshot
      elsif !node.childSnapshotList.empty?
        snapshot = find_node(node.childSnapshotList, name)
      end
    end
    return snapshot
  end

# Displays the chain of snapshots for a vm
   def display_node(node, current, shift=1)
    	out = ""
        out << "+--"*shift
	    if node.snapshot == current
	      out << "CURRENT#{node.name}" << "\n"
	    else
	      out << "#{node.name}" << "\n"
	    end
	    if !node.childSnapshotList.empty?
	      node.childSnapshotList.each { |item| out << display_node(item, current, shift+1) }
	    end
	    out
   end

# Revert the vm to a previous snapshot state 
      def revertToSnapshot(snapshotName)
	if @vm.snapshot
	      snapshot_list = @vm.snapshot.rootSnapshotList
	      current_snapshot = @vm.snapshot.currentSnapshot
	end
        #snapshot_list.each { |i| puts display_node(i, current_snapshot) }
        snapshot = find_node(snapshot_list, snapshotName)
	snapshot.RevertToSnapshot_Task(:suppressPowerOn => false).wait_for_completion
      end

# Deletes a  snapshot 
      def deleteSnapshot(snapshotName)
	if @vm.snapshot
	      snapshot_list = @vm.snapshot.rootSnapshotList
	      current_snapshot = @vm.snapshot.currentSnapshot
	end
        #snapshot_list.each { |i| puts display_node(i, current_snapshot) }
        snapshot = find_node(snapshot_list, snapshotName)
	snapshot.RemoveSnapshot_Task(name:snapshotName, removeChildren:true).wait_for_completion
      end

# Creates a new snapshot. As a side effect, this updates the current snapshot
      def createSnapshot(snapshotName)
        @vm.CreateSnapshot_Task(name:snapshotName,memory:true,quiesce:false).wait_for_completion
        #@vm.CreateSnapshot_Task("new")
      end

      def copy_file(filename,file)
        filepath = "C:\\#{filename}" #put md5 hash

        begin
          url = @fm.InitiateFileTransferToGuest(:vm => @vm, :auth=> @auth, :guestFilePath=> filepath, :fileSize => file.size, :fileAttributes => '', :overwrite => true).sub('*:443', @server)

          RestClient.put(url, file)

        rescue RbVmomi::Fault
          LOGGER.error "VSM", "Fail to copy the file #{file} to #{@vm}: #{$!}"
          abort
        end

      end

      def exec_file(filename, program)
        program["prog_args"].nil? ? args = "" : args = program["prog_args"]
        args += " #{filename}"
puts filename
        #cmd = { :programPath => program["prog_path"], :arguments => args }
        cmd = { :programPath => filename, :arguments => "" }
        pid = @pm.StartProgramInGuest(:vm => @vm , :auth => @auth, :spec => cmd )
        pid.to_i
      end

      def exec_file_raw(filename, arguments="")
        filepath = "C:\\#{filename}"
        cmd = { :programPath => filepath, :arguments => arguments }
        pid = @pm.StartProgramInGuest(:vm => @vm , :auth => @auth, :spec => cmd )
        pid.to_i
      end

      def check_internet
        exec_file_raw("windows\\system32\\ping.exe", "-n 1 www.google.com")  #make www.google.com customizable, move to doroconf
      end

      def get_status(pid)
        p = get_running_procs(pid)
        p["exitCode"]
      end

      def get_running_procs(pid=nil, save_tofile=false, filename="#{DoroSettings.env[:home]}/etc/baseline_processes.yml")
        pid = Array(pid) unless pid.nil?
        @pp2 = Hash.new
        procs = @pm.ListProcessesInGuest(:vm => @vm , :auth => @auth, :pids => pid )
        procs.each {|pp2| @pp2.merge! Hash[pp2.pid, Hash["pname", pp2.name, "owner", pp2.owner, "cmdLine", pp2.cmdLine, "startTime", pp2.startTime, "endTime", pp2.endTime, "exitCode", pp2.exitCode]]}
        if save_tofile
          Util.write(filename, @pp2.to_yaml)
          LOGGER.info "VSM", "Current running processes saved to #{filename}"
        end
        @pp2
      end

      def get_new_procs(current_procs, original_procs=BASELINE_PROCS)
        @new_procs = Hash.new
        current_procs.each_key {|pid|
          @new_procs.merge!(Hash[pid, current_procs[pid]]) unless original_procs.has_key?(pid)
        }
        @new_procs
      end

      def get_files(path)
        fm_files = @fm.ListFilesInGuest(:vm => @vm, :auth=> @auth, :filePath=> path).files
        @files = Hash.new
        fm_files.each {|file|
          @files.merge!(Hash[file.path, Hash[:size, file.size, :type, file.type, :attrs, file.attributes]])
        }
        @files
      end

      def screenshot
        a = @vm.CreateScreenshot_Task.wait_for_completion.split(" ")
        screenpath = "/vmfs/volumes/" + a[0].delete("[]") + "/" + a[1]
        return screenpath
      end

    end

    #Empty method for showing how it could be easy to extend the dorothy's VSM with another virtual manager.
    class VirtualBox
      def initialize

      end

      def revert_vm

      end

      def copy_file

      end

      def exec_file

      end

      def check_internet

      end

      def get_status

      end

      def screenshot

      end

    end
  end


end




