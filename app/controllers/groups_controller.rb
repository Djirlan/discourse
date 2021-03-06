class GroupsController < ApplicationController

  def show
    render_serialized(find_group(:id), BasicGroupSerializer)
  end

  def counts
    group = find_group(:group_id)
    render json: {counts: { posts: group.posts_for(guardian).count,
                            members: group.users.count } }
  end

  def posts
    group = find_group(:group_id)
    posts = group.posts_for(guardian, params[:before_post_id]).limit(20)
    render_serialized posts.to_a, GroupPostSerializer
  end

  def members
    group = find_group(:group_id)

    limit = (params[:limit] || 50).to_i
    offset = params[:offset].to_i

    total = group.users.count
    members = group.users.order('NOT group_users.owner').order(:username_lower).limit(limit).offset(offset)
    owners = group.users.order(:username_lower).where('group_users.owner')

    render json: {
      members: serialize_data(members, GroupUserSerializer),
      owners: serialize_data(owners, GroupUserSerializer),
      meta: {
        total: total,
        limit: limit,
        offset: offset
      }
    }
  end

  def add_members
    group = Group.find(params[:id])
    guardian.ensure_can_edit!(group)

    if params[:usernames].present?
      users = User.where(username: params[:usernames].split(","))
    elsif params[:user_ids].present?
      users = User.find(params[:user_ids].split(","))
    elsif params[:user_emails].present?
      users = User.where(email: params[:user_emails].split(","))
    else
      raise Discourse::InvalidParameters.new('user_ids or usernames or user_emails must be present')
    end

    users.each do |user|
      if !group.users.include?(user)
        group.add(user)
      else
        return render_json_error I18n.t('groups.errors.member_already_exist', username: user.username)
      end
    end

    if group.save
      render json: success_json
    else
      render_json_error(group)
    end
  end

  def remove_member
    group = Group.find(params[:id])
    guardian.ensure_can_edit!(group)

    if params[:user_id].present?
      user = User.find(params[:user_id])
    elsif params[:username].present?
      user = User.find_by_username(params[:username])
    else
      raise Discourse::InvalidParameters.new('user_id or username must be present')
    end

    user.primary_group_id = nil if user.primary_group_id == group.id

    group.users.delete(user.id)

    if group.save && user.save
      render json: success_json
    else
      render_json_error(group)
    end

  end

  private

    def find_group(param_name)
      name = params.require(param_name)
      group = Group.find_by("lower(name) = ?", name.downcase)
      guardian.ensure_can_see!(group)
      group
    end

    def the_group
      @the_group ||= find_group(:group_id)
    end

end
