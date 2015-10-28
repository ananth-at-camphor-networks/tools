#!/usr/bin/env ruby
#
require 'optparse'
require 'ostruct'

@verbose = false

def sh(cmd)
    puts cmd if @options.debug
    o = `#{cmd}`
    puts o if @options.debug
    return $?.to_i == 0
end

def compile (file)
    fl = file.gsub("\.cc", "")
    cmd = "g++ -o #{fl}.o -c -g -O0 -DDEBUG -Wfatal-errors -Wall -Werror -Wsign-compare -Wno-unused-local-typedefs -DLINUX #{@options.additional_include_paths} -Icontroller/lib -Ibuild/include/thrift -Icontroller/src -Ibuild/include -Ibuild/debug -Ibuild/debug/analytics -Ibuild/debug/base -Ibuild/debug/bfd -Ibuild/debug/bgp -Ibuild/debug/cdb -Ibuild/debug/config -Ibuild/debug/contrail-snmp-collector -Ibuild/debug/contrail-topology -Ibuild/debug/control-node -Ibuild/debug/db -Ibuild/debug/discovery -Ibuild/debug/dns -Ibuild/debug/gendb -Ibuild/debug/http -Ibuild/debug/ifmap -Ibuild/debug/io -Ibuild/debug/ksync -Ibuild/debug/net -Ibuild/debug/opserver -Ibuild/debug/query_engine -Ibuild/debug/route -Ibuild/debug/sandesh -Ibuild/debug/schema -Ibuild/debug/server-manager -Ibuild/debug/storage -Ibuild/debug/tools -Ibuild/debug/vnsw -Ibuild/debug/vrouter -Ibuild/debug/xml -Ibuild/debug/xmpp #{fl}.cc"

#   cmd = "g++ -o #{fl}.o -c -g -O0 -DDEBUG -Wfatal-errors -Wall -Werror -Wsign-compare -Wno-unused-local-typedefs -DLINUX -Icontroller/src -Ibuild/include -Icontroller/lib -Ibuild/debug -Ibuild/debug/bgp -Icontroller/src/bgp -Ibuild/debug/io -Icontroller/src/io -Ibuild/debug/db -Icontroller/src/db #{fl}.cc 2>/dev/null"
    result = sh(cmd)
    `rm -rf #{fl}.o 2>/dev/null`
    return result
end

def test (file)
    puts "Processing file #{file}"
    `\grep "^#include " #{file}`.split(/\n/).each { |ifile|
        ifile.chomp!
        next if ifile !~ /^#include\s+(.*)\.h/
        incfile = $1
        incfile.gsub!(/\"/, "")
        next if incfile.end_with? File.basename(file, File.extname(file))
        `cp #{file} #{file}.bak`
        File.open("#{file}.bak", "r") { |fp|
            File.open(file, "w") { |wfp|
                fp.readlines.each { |line|
                    line.gsub!(/\s+$/, "") if @options.delete_trailing_spaces
                    if !@options.delete_unused_includes or line !~ /^#{ifile}/
                        wfp.puts line
                    else
                        puts "Skip #{ifile}" if @options.debug
                    end
                }
            }
        }
        sh("cp #{file}.bak #{file}") if not compile(file)
    }
    `rm -rf #{file}.bak 2>/dev/null`
end

def run
    Dir.chdir @options.root_dir
    ARGV.each { |entry|
        count = 0
        if Dir.directory? entry
            `find #{entry} -name "*.cc"`.split(/\n/).each { |file|
                Process.fork { test(file) }
            }
        else
            Process.fork { test(entry) }
        end
        count += 1; Process.waitall if count % @options.jobs == 0
    }
    Process.waitall
end

def process_args
    @options = OpenStruct.new
    @options.jobs = 4
    @options.delete_trailing_spaces = true
    @options.delete_unused_includes = true
    @options.root_dir = ENV['PWD']
    @options.debug = false
    @options.additional_include_paths = ""

    opt_parser = OptionParser.new { |o|
        o.banner = "Usage: #{$0} [options] {target-directories-to-process}"
        o.on("-j", "--jobs [#{@options.jobs}]",
             "Maximum number of parallel jobs to run") { |j|
            @options.jobs = j.to_i
        }
        o.on("-s", "--[no-]delete-trailing-spaces",
             "[#{@options.delete_trailing_spaces}]",
             "Delete trailing spaces") { |s|
                 @options.delete_trailing_spaces = s
        }
        o.on("-I", "--additional-include-paths [#{@options.additional_include_paths}]",
             "Additional include paths for compilation") { |p|
                 @options.additional_include_paths = p
        }
        o.on("-i", "--[no-]delete-unused-includes",
             "[#{@options.delete_unused_includes}]",
             "Delete unused include files") { |i|
                 @options.delete_unused_includes = i
        }
        o.on("-r", "--root-dir [#{@options.root_dir}]",
             "Contrail sandbox root directory") { |d| @options.root_dir = d }
        o.on("-d", "--[no-]-debug", "[#{@options.debug}]",
             "Show debug information") { |d| @options.debug = d }
    }
    opt_parser.parse!(ARGV)
    if ARGV.empty?
        puts "Please provide at least one target directory to process"
        exit
    end
end

def main
    process_args
    run
end

main
