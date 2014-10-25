class AssociationCache
  attr_reader :course,
              :course_user_data,
              :assessments,
              :sorted_assessments,
              :auds,
              :latest_submissions,
              :latest_submission_scores,
              :assessments_before,
              :assessment_categories

  def initialize(course)
    @course = course
    yield self
    setup_associations
  end

  def load_course_user_data(find_options = {})
    @course_user_data = {}
    @course.course_user_data.where(find_options[:conditions]).each do |cud|
      @course_user_data[cud.id] = cud
    end
  end

  def load_assessments(find_options = {})
    @assessments = {}
    @sorted_assessments = @course.assessments.ordered.load
    setup_assessments_before @sorted_assessments
    @sorted_assessments.each do |asmt|
      @assessments[asmt.id] = asmt
    end
  end

  def load_assessment_categories(find_options = {})
    @assessment_categories = {}
    @course.assessment_categories.where(find_options[:conditions]).each do |cat|
      @assessment_categories[cat.id] = cat
    end
  end

  # NOTE
  # might need to batch this (find_each) at some point.
  # as of 4/1/13, faster unbatched.
  def load_auds(find_options = {})
    @auds = {}
    @course.assessment_user_data.where(find_options[:conditions]).each do |aud|
      @auds[au_key aud.assessment_id, aud.course_user_datum_id] = aud
    end
  end

  def load_latest_submissions(find_options = {})
    @latest_submissions = {}
    @course.submissions.latest.where(find_options[:conditions]).each do |sub|
      @latest_submissions[au_key sub.assessment_id, sub.course_user_datum_id] = sub
    end
  end

  def load_latest_submission_scores(find_options = {})
    @latest_submission_scores = {}
    Score.on_latest_submissions.for_course(@course).where(find_options[:conditions]).each do |score|
      @latest_submission_scores[score.submission_id] = [] unless @latest_submission_scores[score.submission_id]
      @latest_submission_scores[score.submission_id] << score
    end
    @latest_submission_scores.default = []
  end

private
  def setup_associations
    @assessments.each_value { |asmt|
      asmt.association_cache = self
    } if @assessments

    (@auds.each_value { |aud| 
      aud.association_cache = self
    }) if @auds

    (@latest_submissions.each_value { |ls|
      ls.association_cache = self
    }) if @latest_submissions

    @course.association_cache = self

    @course_user_data.each_value { |cud|
      cud.association_cache = self
    } if @course_user_data
  end

  def setup_assessments_before(sorted_assessments)
    @assessments_before = {}
    sorted_assessments.each_with_index { |asmt, i|
      @assessments_before[asmt.id] = sorted_assessments[i - 1] if i > 0
    }
  end
end

def au_key(assessment_id, cud_id)
  "a_#{assessment_id}/u_#{cud_id}"
end

module CUDAssociationCache
  def self.included(base)
    base.alias_method_chain :course, :cache
  end

  def course_with_cache
    @course || course_without_cache
  end

  def association_cache=(cache)
    @ass_cache = cache

    @course = cache.course if cache.course
  end
end

module CourseAssociationCache
  def self.included(base)
    base.alias_method_chain :course_user_data, :cache
    base.alias_method_chain :assessments, :cache
    base.alias_method_chain :assessment_categories, :cache
  end

  def course_user_data_with_cache
    @course_user_data || course_user_data_without_cache
  end

  def assessments_with_cache
    @assessments || assessments_without_cache
  end

  def assessment_categories_with_cache
    @assessment_categories || assessment_categories_without_cache
  end

  def association_cache=(cache)
    @ass_cache = cache

    @cuds = cache.course_user_data.values if cache.course_user_data
    @assessments = cache.sorted_assessments if cache.sorted_assessments
    @assessment_categories = cache.assessment_categories.values if cache.assessment_categories
  end
end

module AssessmentAssociationCache
  def self.included(base)
    base.alias_method_chain :assessment_before, :cache
    base.alias_method_chain :aud_for, :cache
    base.alias_method_chain :course, :cache
  end

  def assessment_before_with_cache
    asmt_before_cache = @ass_cache && @ass_cache.assessments_before
    asmt_before_cache ? asmt_before_cache[id] : assessment_before_without_cache 
  end

  def aud_for_with_cache(cud_id)
    aud_cache = @ass_cache && @ass_cache.auds
    aud_cache ? aud_cache[au_key id, cud_id] : aud_for_without_cache(cud_id)
  end

  def course_with_cache
    @course || course_without_cache
  end

  def association_cache=(cache)
    @ass_cache = cache

    @course = cache.course if cache.course
  end
end

module AUDAssociationCache
  def self.included(base)
    base.alias_method_chain :assessment, :cache
    base.alias_method_chain :course_user_datum, :cache
    base.alias_method_chain :latest_submission, :cache
  end

  def latest_submission_with_cache
    @latest_submission || latest_submission_without_cache
  end

  def course_user_datum_with_cache
    @cud || course_user_datum_without_cache
  end

  def assessment_with_cache
    @assessment || assessment_without_cache
  end
  def association_cache=(cache)
    @ass_cache = cache

    @assessment = cache.assessments[assessment_id] if cache.assessments
    @cud = cache.course_user_data[course_user_datum_id] if cache.course_user_data
    @latest_submission = cache.latest_submissions[au_key assessment_id, course_user_datum_id] if cache.latest_submissions
  end
end

module LatestSubmissionAssociationCache
  def self.included(base)
    base.alias_method_chain :assessment, :cache
    base.alias_method_chain :course_user_datum, :cache
    base.alias_method_chain :aud, :cache
    base.alias_method_chain :scores, :cache
  end

  def aud_with_cache
    @aud || aud_without_cache
  end

  def course_user_datum_with_cache
    @cud || course_user_datum_without_cache
  end

  def assessment_with_cache
    @assessment || assessment_without_cache
  end

  def scores_with_cache
    @scores || scores_without_cache
  end

  def association_cache=(cache)
    @ass_cache = cache

    @assessment = cache.assessments[assessment_id] if cache.assessments
    @cud = cache.course_user_data[course_user_datum_id] if cache.course_user_data
    @aud = cache.auds[au_key assessment_id, course_user_datum_id] if cache.auds
    @scores = cache.latest_submission_scores[id] if cache.latest_submission_scores
  end
end
