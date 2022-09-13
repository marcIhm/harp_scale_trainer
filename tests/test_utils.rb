#
# Utilities for testing with run.rb
#

def new_session x = $term_min_width, y = $term_min_height
  kill_session 
 #
  # The simple command below does not work because of a bug in tmux 3.2a:
  # (use 'tmux -V' to get version)
  #
  #   sys "tmux -u new-session -d -x #{$term_min_width} -y #{$term_min_height} -s ht"
  #
  # So we use a workaround according to https://unix.stackexchange.com/questions/359088/how-do-i-force-a-tmux-window-to-be-a-given-size
  #
  system "rm -rf /tmp/harpwise*-* >/dev/null 2>&1"
  %w(start end).each do |marker|
    File.delete($testing_dump_template % marker) if File.exist?($testing_dump_template % marker)
  end
  FileUtils.rm($pipeline_started) if File.exist?($pipeline_started)
  sys "tmux new-session -d -x #{x} -y #{y} -s harpwise \\; new-window bash \\; kill-window -t 0"
  tms 'cd ~'
  tms :ENTER
  tms 'PS1=\"\$ \"'
  tms :ENTER
  tms 'clear'
  tms :ENTER
end


def kill_session
  system "tmux kill-session -t harpwise >/dev/null 2>&1"
end


def sys cmd
  out, stat = Open3.capture2e(cmd)
  stat.success? || fail("Command '#{cmd}' failed with:\n#{out}")
end
  

def tms cmd
  # let typed command appear on screen
  sleep 0.5
  if cmd.is_a?(Symbol)
    sys "tmux send -t harpwise #{cmd.to_s.tr('_','-')}"
  else
    sys "tmux send -l -t harpwise \"#{cmd}\""
  end
  sleep 0.5
end


def screen
  %x(tmux capture-pane -t harpwise -p).lines.map!(&:chomp)
end


def wait_for_start_of_pipeline
  20.times do
    if File.exist?($pipeline_started)
      sleep 1
      return
    end
    sleep 1
  end
  pp screen
  fail "Pipeline did not start OR harpwise has not been started wih '--testing' OR harpwise did not even initialize completely"
end


def wait_for_end_of_harpwise
  20.times do
    unless Sys::ProcTable.ps.any? {|p| p.cmdline['harpwise'] && p.cmdline['ruby']}
      sleep 1
      return
    end
    sleep 1
  end
  pp screen
  fail "harpwise did not come to an end"
end


def expect *failinfo, &block
  5.times do 
    if yield
      print "\e[32mOkay \e[0m"
      return
    end
    sleep 1
  end
  
  puts
  source = block.to_source
  pp screen if source['screen']
  puts "\e[31mNOT Okay\e[0m"
  puts source
  pp failinfo if failinfo.length > 0
  kill_session
  exit 1
end

def sound secs, semi
    sys "sox -n /tmp/harpwise_testing.wav synth #{secs} sawtooth %#{semi} gain -n -3"
end


$memo_file = "/tmp/harpwise_testing_memo.json"
$last_test = "/tmp/harpwise_testing_last_tried.json"
$memo_count = 0
$memo_seen = Set.new
$memo = File.exist?($memo_file)  ?  JSON.parse(File.read($memo_file))  :  {count: '?', durations: {}}
$memo.transform_keys!(&:to_sym)
$fromon_id_uniq = Set.new

def do_test text
  $memo_count += 1
  if md = text.match(/#{$fromon_id_regex}/)
    id = md[1]
    fail "Test-id #{id} has already appeared" if $fromon_id_uniq.include?(id)
    $fromon_id_uniq << id
  else
    fail "Test '#{text}' should start with an id"
  end
  File.write $last_test, JSON.pretty_generate({time: Time.now, id: id}) + "\n"
  $within = true if ( $fromon_cnt && $memo_count == $fromon_cnt ) ||
                    ( $fromon_id && text.start_with?($fromon_id))
  ( $fromon && text[$fromon] )
  return unless $within
  puts
  [$testing_dump_template % 'start', $testing_dump_template % 'end', $testing_log_file].each do |file|
    File.delete(file) if File.exists?(file)
  end
  $memo_seen << text
  klens = $memo[:durations].keys.map(&:length).sort
  most_ian = klens[klens.length * 3.to_f / 4] || 0
  time = $memo[:durations][text]
  print "  #{text.ljust(most_ian)}   #{$memo_count.to_s.rjust(2)} of #{$memo[:count].to_s.rjust(2)}    #{time ? ('%5.1f' % time) : '?'} secs ... "
  FileUtils.cp '/tmp/harpwise_testing.wav_default','/tmp/harpwise_testing.wav'
  start = Time.now.to_f
  yield
  $memo[:durations][text] = Time.now.to_f - start
end


def read_testing_dump marker
  JSON.parse(File.read($testing_dump_template % marker), symbolize_names: true)
end


def read_testing_log
  File.readlines($testing_log_file)
end


def clear_testing_log
  FileUtils.rm($testing_log_file) if File.exist?($testing_log_file)
end


def move_dotdir
  move_or_backup_dotdir :move
end


def backup_dotdir 
  move_or_backup_dotdir :backup
end


def move_or_backup_dotdir what
  check_dotdir_state
  $dotdir_state_unknown = true
  case what
  when :move
    FileUtils.mv $dotdir, $dotdir_saved
  when :backup
    FileUtils.cp_r $dotdir, $dotdir_saved
  else
    fail "Internal error"
  end
  $dotdir_state_unknown = false
end


def check_dotdir_state
  $dotdir_state_unknown = true
  if File.exist?($dotdir_saved)
    fail "Saved dot-dir #{$dotdir_saved} already exists; a previous run might have failed. Please check its content and *maybe* rename it to #{$dotdir}"
  end
  unless File.exist?($dotdir)
    fail "Dot-dir #{$dotdir} does not exist; a previous run might have failed. Please check its content and *maybe* rename it to #{$dotdir_saved}"
  end
  $dotdir_state_unknown = false
end
  

def restore_dotdir regular: true
  unless File.directory?($dotdir_saved)
    if regular
      $dotdir_state_unknown = true
      fail "Expected save #{$dotdir_saved} does not exist" 
    end
    return
  end
  $dotdir_state_unknown = true
  FileUtils.rm_r $dotdir
  FileUtils.mv $dotdir_saved, $dotdir
  puts "Restored #{$dotdir} from #{$dotdir_saved}" unless regular
  $dotdir_state_unknown = false
end


at_exit {
  if $dotdir_state_unknown
    if $dotdir && $dotdir_saved
      puts "State of #{$dotdir} is unknown (see above); not trying to restore from #{$dotdir_saved}"
    else
      # early fail
    end
  else
    restore_dotdir regular: false
  end
  if $!.nil?
    $memo[:count] = $memo_count
    $memo[:durations].each_key {|k| $memo[:durations].delete(k) unless $memo_seen === k}
  end
  File.write($memo_file, JSON.pretty_generate($memo)) if $fromon.empty?
}
