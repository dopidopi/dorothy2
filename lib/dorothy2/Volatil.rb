module Dorothy

  module Volatil
    extend self
    require 'colorize'

    def imageinfo(file, profile)
    end
	
    def VMSN2Raw(folder,file)
	fullname=folder+file
	puts "convierte:"+fullname
	#o=`vol imagecopy -f #{folder}#{file} -O #{folder}memfile.dd`
	o=`vol imagecopy -f #{fullname.strip!} -O #{folder}memfile.dd 2>/dev/null`
	puts o
	return folder+"memfile.dd"
    end

    def RogueProcesses(memfile)
	#o=`vol psxview -f #{memfile}`
	puts 'Rogue Processes'
	puts '---------------'
	o=IO.popen('vol psxview -f '+memfile+' 2>/dev/null')
	o.each_line do |line|
		data = line.split
		pslist = data[3]
		psscan = data[4]
		if ['True','False'].include? pslist
			if pslist!=psscan
				puts line.red
				#puts 'Process name:'+data[1]+' PID:'+data[2]
			else
				puts line
			end
		end
	end
	
    end

    def NetConnections(memfile)
	#o=`vol connscan -f #{memfile}`
	puts 'Rogue Connections'
	puts '---------------'
	o=IO.popen('vol connscan -f '+memfile+' 2>/dev/null')
	o.each_line do |line|
		data = line.split
		sourceip = data[1].split(/:/)[0]
		sourceport = data[1].split(/:/)[1]
		destip = data[2].split(/:/)[0]
		destport = data[2].split(/:/)[1]
		if sourceip=='192.168.10.55'
			puts line.red
		else
			puts line	
		end
	end
    end

    def AutoRun(memfile)
	#o=`vol printkey -f #{memfile} -K 'Software\\Microsoft\\Windows\\CurrentVersion\\Run'`
	puts 'Persistence Registry Keys'
	puts '-------------------------'
	o=IO.popen('vol printkey -f '+memfile+' -K \'Software\\Microsoft\\Windows\\CurrentVersion\\Run\''+' 2>/dev/null')
	o.each_line do |line|
		puts line
	end
	
    end

    def CodeInjection(memfile)
	#o=`vol malfind -f #{memfile}`
	puts 'Code Injection'
	puts '--------------'
	o=IO.popen('vol malfind -f '+memfile+' 2>/dev/null')
	o.each_line do |line|
		puts line
	end
    end

    def CodeInjection2(memfile)
	o=`vol ldrmodules -f #{memfile}`
	puts o
    end
	
  end

end
