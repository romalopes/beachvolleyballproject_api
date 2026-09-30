class CreateOrganisationMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :organisation_memberships do |t|
      t.references :organisation, null: false, foreign_key: true
      # Person, never User or a profile: a Person is the domain identity whether or
      # not they have an account, and whether or not they happen to be a player. A
      # membership that required an Account would exclude exactly the people a club
      # most needs to record — a volunteer coach, a parent, a committee member.
      t.references :person, null: false, foreign_key: true

      # What the person does *for this organisation*, which is not the same fact as
      # whether they are a beach volleyball coach anywhere. A national coach can be an
      # ordinary member of one club and the owner of an academy.
      t.string :role, null: false, default: "member"
      # A lifecycle rather than a deletion: someone who leaves is still recorded as
      # having been there, which is what makes a historical assessment explicable.
      t.string :status, null: false, default: "pending"
      t.datetime :joined_at
      t.datetime :left_at

      t.timestamps
    end

    # One row per person per organisation, reused across leaving and rejoining. A
    # second row would make "is this person currently a member?" ambiguous.
    add_index :organisation_memberships, [ :organisation_id, :person_id ],
              unique: true, name: "index_org_memberships_on_organisation_and_person"
    # `person_id` is indexed already by `t.references` above; only the composite
    # with status is worth adding, because "every active member of this club" is the
    # query every visibility rule below depends on.
    add_index :organisation_memberships, [ :organisation_id, :status ],
              name: "index_org_memberships_on_organisation_and_status"

    # At most one *active* owner per organisation, enforced by the database rather
    # than only by a model check — this is the one rule where a race would leave an
    # organisation with two owners and no way to pick between them.
    add_index :organisation_memberships, :organisation_id,
              unique: true,
              where: "role = 'owner' AND status = 'active'",
              name: "index_org_memberships_single_active_owner"

    add_check_constraint :organisation_memberships,
                         "role::text = ANY (ARRAY['owner'::character varying::text, " \
                         "'administrator'::character varying::text, " \
                         "'coach'::character varying::text, " \
                         "'member'::character varying::text])",
                         name: "organisation_memberships_role"

    add_check_constraint :organisation_memberships,
                         "status::text = ANY (ARRAY['pending'::character varying::text, " \
                         "'active'::character varying::text, " \
                         "'suspended'::character varying::text, " \
                         "'ended'::character varying::text])",
                         name: "organisation_memberships_status"

    # `left_at` belongs to `ended` and to nothing else, so the two can never disagree
    # about whether somebody actually left.
    add_check_constraint :organisation_memberships,
                         "status::text <> 'ended'::text OR left_at IS NOT NULL",
                         name: "organisation_memberships_ended_has_left_at"
  end
end
