#
# Perform quiz
#

def do_quiz

  prepare_term
  start_kb_handler
  start_collect_freqs
  
  puts "\n\nAgain and again: Hear #{$num_quiz} note(s) from the scale and then try to replay ..."
  [2,1].each do |c|
    puts c
    sleep 1
  end

  first_lap = true
  all_wanted_before = all_wanted = nil
  $ctl_can_next = true
  loop do   # forever until ctrl-c, sequence after sequence

    unless first_lap
      print "\e[#{$line_issue}H\e[K" 
      ctl_issue
      print "\e[#{$line_hint}H\e[K" 
      print "\e[#{$line_listen}H\e[K"
      print "\e[#{$line_listen2}H\e[K"
    end

    if $ctl_back
      if !all_wanted_before || all_wanted_before == all_wanted
        print "no previous sequence; restarting "
        sleep 1
      else
        all_wanted = all_wanted_before
        print "\e[32mto previous sequence\e[0m "
        sleep 1
      end
      $ctl_loop = true
    else
      all_wanted_before = all_wanted
      all_wanted = get_sample($num_quiz)
      $ctl_loop = $opts[:loop]
    end
    $ctl_back = $ctl_next = false
    
    sleep 0.3

    all_wanted.each_with_index do |hole, idx|
      if idx > 0
        isemi, itext = describe_inter(hole, all_wanted[idx - 1])
        print "\e[2m" + ( itext || "#{isemi}" ) + "\e[0m "
      end
      print "\e[2m#{$harp[hole][:note]}\e[0m listen ... "
      play_thr = Thread.new { play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]) }
      begin
        # do some recording to drain samples, that only recorded, what we have just played.
        sleep 0.1
        handle_kb_listen
      end while play_thr.alive?
      play_thr.join   # raises any errors from thread
      break if $ctl_back
    end
    redo if $ctl_back
    print "\e[32mand !\e[0m"
    sleep 0.5

    print "\e[#{$line_listen}H\e[K\e[#{$line_listen2}H\e[K" unless first_lap
  
    system('clear') if first_lap
    full_hint_shown = false

    begin   # while looping over one sequence

      lap_start = Time.now.to_f

      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one lap while looping

        hole_start = Time.now.to_f
        pipeline_catch_up

        get_hole(
          if $ctl_loop
            "\e[32mLooping\e[0m over #{all_wanted.length} notes; play them again and again ..."
          else
            if $num_quiz == 1 
              "Play the note you have heard !"
            else
              "Play note number \e[32m#{idx+1}\e[0m from the sequence of #{$num_quiz} you have heard !"
            end
          end,
          -> (played, since) {[played == wanted,  # lambda_good_done
                               played == wanted && 
                               Time.now.to_f - since > 0.5]}, # do not return okay immediately
          
          -> () {$ctl_next || $ctl_back},  # lambda_skip
          
          -> (_, _, _, _, _) do  # lambda_comment_big
            if $num_quiz == 1
              [ "\e[2m", '.  .  .', 'smblock' ]
            else
              [ "\e[2m", 'Yes  ' + (idx == 0 ? '' : all_wanted[0 .. idx - 1].join(' ')) + ' _' * (all_wanted.length - idx), 'smblock' ]
            end
          end,
          
          -> (_) do  # lambda_hint
            hole_passed = Time.now.to_f - hole_start
            lap_passed = Time.now.to_f - lap_start

            if all_wanted.length > 1 &&
               hole_passed > 4 &&
               lap_passed > ( full_hint_shown ? 3 : 6 ) * all_wanted.length
              print "Solution: The complete sequence is: #{describe_sequence(all_wanted)}\e[0m" 
              full_hint_shown = true
            elsif hole_passed > 4
              print "Hint: Play \e[32m#{wanted}\e[0m"
            else
              if idx > 0
                isemi, itext = describe_inter(wanted, all_wanted[idx - 1])
                if isemi
                  print "\e[2mHint: Move "
                  print ( itext ? "a #{itext}" : isemi )
                end
              end
            end
            print "\e[K"
          end,

          -> (_) { idx > 0 && all_wanted[idx - 1] })  # lambda_hole_for_inter

        print "\e[#{$line_comment_small}H\e[K"

      end # notes in a sequence

      if $ctl_next || $ctl_back
        print "\e[#{$line_issue}H#{''.ljust($term_width - $ctl_issue_width)}"
        first_lap = false
        next
      end
    
      print "\e[#{$line_comment_big}H"
      text = if $ctl_next
               "skip"
             elsif $ctl_back
               "jump back"
             else
               ( full_hint_shown ? 'Yes ' : 'Great ! ' ) + all_wanted.join(' ')
             end
      print "\e[32m"
      do_figlet text, 'smblock'
      print "\e[0m"
      
      print "\e[#{$line_comment_small}H"
      print "#{$ctl_next || $ctl_back ? 'T' : 'Yes, t'}he sequence was: #{describe_sequence(all_wanted)}   ...   "
      print "\e[0m\e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !\e[K"
      full_hint_shown = true
    
      sleep 1
    end while $ctl_loop && !$ctl_back && !$ctl_next  # looping over one sequence

    first_lap = false
  end # sequence after sequence
end


def get_sample num
  # construct chains of holes within scale using one of these:
  # - random holes from the scale
  # - intervals within an octave
  # - named intervals
  holes = Array.new
  holes[0] = $scale_holes.sample
  semi2hole = $scale_holes.map {|hole| [$harp[hole][:semi], hole]}.to_h
  ran = rand
  for i in (1 .. num - 1)
    if ran > 0.8
      holes[i] = $scale_holes.sample
      elsif ran > 0.4
      begin
        try_semi = $harp[holes[i-1]][:semi] + rand(12)
      end until semi2hole[try_semi]
      holes[i] = semi2hole[try_semi]
    else
      begin 
        try_inter = $intervals.keys.sample * ( rand >= 0.5 ? 1 : -1 )
        try_semi = $harp[holes[i-1]][:semi] + try_inter
      end until semi2hole[try_semi]
      holes[i] = semi2hole[try_semi]
    end
  end
  holes
end


def describe_sequence holes
  desc = holes[0]
  holes.each_cons(2) do |h1, h2|
    di = describe_inter(h1,h2)
    desc += " \e[2m(#{di[1] || di[0]})\e[0m #{h2} "
  end
  desc.rstrip
end
  
