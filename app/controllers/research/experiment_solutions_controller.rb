module Research
  class ExperimentSolutionsController < Research::BaseController
    def create
      experiment = Experiment.find(params[:experiment_id])

      exercise_slug = "#{params[:language]}-#{params[:part]}-#{%w{a b}.sample}"
      exercise = Exercise.find_by_slug!(exercise_slug)

      # Guard to ensure that someone doesn't try and access
      # a non-research solution through this method.
      raise "Incorrect exercise" unless exercise.track.research_track?

      solution = Research::CreateSolution.(
        current_user,
        experiment,
        exercise
      )

      redirect_to research_experiment_solution_path(solution)
    end

    def show
      @solution = current_user.research_experiment_solutions.find_by_uuid(params[:id])
    end
  end
end
