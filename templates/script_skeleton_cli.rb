#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'open3'

# A lightweight struct to hold the command's execution results cleanly
CommandResult = Struct.new(:success?, :stdout, :stderr, :exit_code, :error_message)

def execute_command(cmd, *args)
  # Open3.capture3 handles execution safely, separating streams and exposing exit status
  stdout_str, stderr_str, status = Open3.capture3(cmd, *args)

  if status.success?
    CommandResult.new(true, stdout_str, stderr_str, status.exitstatus, nil)
  else
    error_msg = "Command '#{cmd}' failed with exit code #{status.exitstatus}."
    CommandResult.new(false, stdout_str, stderr_str, status.exitstatus, error_msg)
  end
rescue Errno::ENOENT => e
  # Caught specifically if the binary/command executable cannot be found on the host system
  error_msg = "System dependency missing: The command '#{cmd}' was not found."
  CommandResult.new(false, '', e.message, nil, error_msg)
rescue => e
  # Catch-all for unexpected low-level environment or system exceptions
  CommandResult.new(false, '', e.message, nil, "Unexpected error: #{e.message}")
end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Input file") {|argument| options.infile = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

result = execute_command("echo", "hello", "world")

if !result.success?
    warn "Failed command with: #{result.error_message}"
end