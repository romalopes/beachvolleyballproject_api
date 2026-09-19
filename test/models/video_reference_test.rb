require "test_helper"

class VideoReferenceTest < ActiveSupport::TestCase
  setup do
    @video = Video.create!(source_url: "https://www.youtube.com/watch?v=ABC123")
  end

  # --- Associations / polymorphism ---

  test "accepts a reference on a drill" do
    reference = VideoReference.new(video: @video, referenced: drills(:one),
                                   start_seconds: 272, end_seconds: 378)
    assert reference.valid?
    assert_equal "Drill", reference.referenced_type
  end

  test "accepts a reference on a skill" do
    reference = VideoReference.new(video: @video, referenced: skills(:one),
                                   start_seconds: 0, end_seconds: 10)
    assert reference.valid?
    assert_equal "Skill", reference.referenced_type
  end

  test "requires a video" do
    reference = VideoReference.new(referenced: drills(:one))
    assert_not reference.valid?
    assert reference.errors[:video].any?
  end

  test "requires a referenced object" do
    reference = VideoReference.new(video: @video)
    assert_not reference.valid?
    assert reference.errors[:referenced].any?
  end

  test "video has many references and a shared video can serve drill and skill" do
    drill_reference = VideoReference.create!(video: @video, referenced: drills(:one))
    skill_reference = VideoReference.create!(video: @video, referenced: skills(:one))
    assert_equal [ drill_reference.id, skill_reference.id ].sort,
                 @video.video_references.map(&:id).sort
  end

  # --- Timestamp validation ---

  test "negative start is rejected" do
    reference = VideoReference.new(video: @video, referenced: drills(:one), start_seconds: -1)
    assert_not reference.valid?
    assert reference.errors[:start_seconds].any?
  end

  test "negative end is rejected" do
    reference = VideoReference.new(video: @video, referenced: drills(:one),
                                   start_seconds: 0, end_seconds: -5)
    assert_not reference.valid?
    assert reference.errors[:end_seconds].any?
  end

  test "end equal to start is rejected when end is provided" do
    reference = VideoReference.new(video: @video, referenced: drills(:one),
                                   start_seconds: 272, end_seconds: 272)
    assert_not reference.valid?
    assert reference.errors[:end_seconds].any?
  end

  test "end before start is rejected" do
    reference = VideoReference.new(video: @video, referenced: drills(:one),
                                   start_seconds: 378, end_seconds: 272)
    assert_not reference.valid?
    assert reference.errors[:end_seconds].any?
  end

  test "end is optional (start-only reference)" do
    reference = VideoReference.new(video: @video, referenced: drills(:one), start_seconds: 272)
    assert reference.valid?, reference.errors.full_messages.to_sentence
  end

  test "timestamps beyond a known duration are rejected" do
    video = Video.create!(source_url: "https://www.youtube.com/watch?v=DUR600TEST",
                          duration_seconds: 600)
    reference = VideoReference.new(video: video, referenced: drills(:one),
                                   start_seconds: 0, end_seconds: 700)
    assert_not reference.valid?
    assert reference.errors[:end_seconds].any?

    reference = VideoReference.new(video: video, referenced: drills(:one),
                                   start_seconds: 0, end_seconds: 600)
    assert reference.valid?
  end

  test "an external video without a known duration is never rejected for timestamps" do
    video = Video.create!(source_url: "https://cdn.example.com/clip.mp4")
    assert_nil video.duration_seconds
    reference = VideoReference.new(video: video, referenced: drills(:one),
                                   start_seconds: 0, end_seconds: 100_000)
    assert reference.valid?, reference.errors.full_messages.to_sentence
  end

  # --- Position ---

  test "position appends within the referenced object" do
    first = VideoReference.create!(video: @video, referenced: drills(:one))
    assert_equal 0, first.position
    second = VideoReference.create!(video: @video, referenced: drills(:one))
    assert_equal 1, second.position
    # A separate drill numbers its own list from the beginning.
    other = VideoReference.create!(video: @video, referenced: drills(:two))
    assert_equal 0, other.position
  end

  # --- Dependent behaviour ---

  test "deleting a drill destroys its references" do
    drill = Drill.create!(title: "Video Drill", setup_instructions: "",
                          training_stage: "middle", difficulty_level: "beginner",
                          min_players: 1, max_players: 2, ideal_num_players: 2)
    VideoReference.create!(video: @video, referenced: drill)
    assert_difference "VideoReference.count", -1 do
      drill.destroy
    end
  end

  test "deleting a skill destroys its references" do
    skill = Skill.create!(title: "Video Skill", category: categories(:one))
    VideoReference.create!(video: @video, referenced: skill)
    assert_difference "VideoReference.count", -1 do
      skill.destroy
    end
  end

  test "deleting a reference never deletes a shared video" do
    drill_reference = VideoReference.create!(video: @video, referenced: drills(:one))
    VideoReference.create!(video: @video, referenced: skills(:one))

    assert_no_difference "Video.count" do
      drill_reference.destroy
    end
    assert_not_nil @video.reload
    assert_equal 1, @video.video_references.count
  end

  test "deleting the last reference also keeps the video" do
    reference = VideoReference.create!(video: @video, referenced: drills(:one))
    reference.destroy
    assert Video.exists?(@video.id)
  end
end
