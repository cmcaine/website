class GenerateMentorHeartbeats
  include Mandate

  def call
    active_mentors.find_each do |mentor|
      email_log = UserEmailLog.for_user(mentor)
      next if email_log.mentor_heartbeat_sent_at.to_i > (Time.current - 6.days).to_i

      if email_log.mentor_heartbeat_sent_at.nil?
        introduction = %q{Starting from today, we'll be sending you a brief weekly summary on the state of each track you're mentoring, along with some information on any changes or updates to the mentoring side of Exercism that have occurred during the week. If you have any thoughts or ideas on what you'd like to see here, please open an issue at on GitHub. If you want to opt out, there's a link at the bottom of the email. Which leaves me just to say a huge thank you for your hard work!}
      end

      merged_stats = {}
      mentor_track_stats = generate_mentor_track_stats(mentor)
      mentor_track_stats.each do |slug, personal_stats|
        merged_stats[slug] = track_stats[slug].clone
        merged_stats[slug][:stats].merge!(personal_stats)
      end
      next if merged_stats.empty?

      DeliverEmail.(
        mentor,
        :mentor_heartbeat,
        { site: site_stats, tracks: merged_stats },
        introduction
      )
    end
  end

  private

  def generate_mentor_track_stats(mentor)
    tracks = Track.where(id: TrackMentorship.where(user: mentor).select(:track_id))
    track_counts = SolutionMentorship.where(user: mentor).
                                      where("solution_mentorships.created_at >= ?", stats_time).
                                      joins(solution: :exercise).
                                      group('exercises.track_id').count

    tracks.each_with_object(Hash.new{|h,k|h[k] = {}}) do |track, data|
      data[track.slug][:solutions_mentored_by_you] = track_counts[track.id].to_i
    end
  end

  memoize
  def site_stats
    num_solutions = submitted_solution_ids.size
    num_solutions_for_mentoring = Solution.where(id: submitted_solution_ids).
                                           where.not(mentoring_requested_at: nil).
                                           count

    num_solution_mentorships = SolutionMentorship.where("created_at >= ?", stats_time).count

    num_learners = Solution.where(id: submitted_solution_ids).
                            select(:user_id).
                            distinct.count

    num_mentors = Solution.where("last_updated_by_mentor_at >= ?", stats_time).
                                        joins(:mentorships).
                                        select('solution_mentorships.user_id').
                                        distinct.count

    {
      num_solutions: num_solutions,
      num_solutions_for_mentoring: num_solutions_for_mentoring,
      num_solution_mentorships: num_solution_mentorships,
      num_learners: num_learners,
      num_mentors: num_mentors
    }
  end

  memoize
  def track_stats
    Track.all.each_with_object({}) do |track, stats|
      track_solutions = Solution.where(id: submitted_solution_ids).
                                    joins(:exercise).where('exercises.track_id': track.id)

      num_solutions = track_solutions.size
      num_solutions_for_mentoring = track_solutions.where.not(mentoring_requested_at: nil).count
      num_solution_mentorships = SolutionMentorship.where("solution_mentorships.created_at >= ?", stats_time).
                                                    joins(solution: :exercise).
                                                    where('exercises.track_id': track.id).
                                                    count

      current_queue_length = Solution.joins(:exercise).where('exercises.track_id': track.id).
                                      submitted.
                                      where.not(mentoring_requested_at: nil).
                                      where(approved_by: nil).
                                      where(completed_at: nil).
                                      where(num_mentors: 0).
                                      count

      stats[track.slug] = {
        title: track.title,
        stats: {
          new_solutions_submitted: num_solutions,
          solutions_submitted_for_mentoring: num_solutions_for_mentoring,
          current_queue_length: current_queue_length,
          total_solutions_mentored: num_solution_mentorships
        }
      }
    end
  end

  def stats_time
    Time.current - 1.week
  end

  def active_mentors
    User.where(id: SolutionMentorship.
                     where("created_at > ?", Time.current - 21.days).
                     select(:user_id).distinct)
  end

  memoize
  def submitted_solution_ids
    Iteration.
      where('created_at >= ?', stats_time).
      where("NOT EXISTS(
               SELECT NULL
               FROM iterations as old_iterations
               WHERE old_iterations.solution_id = iterations.solution_id
               AND created_at < ?
             )", stats_time).
       select(:solution_id).distinct
  end
end

=begin
  * Total number of mentored solutions in total
  * Total number of mentored solutions by me
  * Total number of mentors that have mentored solutions
  * Total number of new submissions per exercise
  * Total number of mentored submissions per exercise
  * Maybe something like average wait time for mentoring per exercise?
  * Maybe average number of iterations before approval per exercise?
  * Total number of solutions
  * Number of core solutions
  * Number of side exercise solutions
  * Mentor rate of core solutions vs side solutions
=end
