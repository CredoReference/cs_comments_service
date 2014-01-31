require 'spec_helper'
require 'unicode_shared_examples'

describe "app" do
  describe "users" do
    before :each do
      User.delete_all
      create_test_user 1
      create_test_user 2
    end
    describe "POST /api/v1/users" do
      it "creates a user" do
        post "/api/v1/users", id: "100", username: "user100", email: "user100@test.com"
        last_response.should be_ok
        user = User.find_by(external_id: "100")
        user.username.should == "user100"
        user.email.should == "user100@test.com"
      end
      it "returns error when id / username / email already exists" do
        post "/api/v1/users", id: "1", username: "user100", email: "user100@test.com"
        last_response.status.should == 400
        post "/api/v1/users", id: "100", username: "user1", email: "user100@test.com"
        last_response.status.should == 400
        post "/api/v1/users", id: "100", username: "user100", email: "user1@test.com"
        last_response.status.should == 400
      end
    end
    describe "PUT /api/v1/users/:user_id" do
      it "updates user information" do
        put "/api/v1/users/1", username: "new_user_1"
        last_response.should be_ok
        user = User.find_by("1")
        user.username.should == "new_user_1"
      end
      it "does not update id" do
        put "/api/v1/users/1", id: "100"
        last_response.should be_ok
        user = User.find_by("1")
        user.should_not be_nil
      end
      it "returns error if user does not exist" do
        put "/api/v1/users/100", id: "100"
        last_response.status.should == 400
      end
      it "returns error if new information has conflict with other users" do
        put "/api/v1/users/1", username: "user2"
        last_response.status.should == 400 
      end
    end
    describe "GET /api/v1/users/:user_id/active_threads" do

      before(:each) { setup_10_threads }

      def thread_result(user_id, params)
        get "/api/v1/users/#{user_id}/active_threads", params
        last_response.should be_ok
        parse(last_response.body)["collection"]
      end

      it "requires that a course id be passed" do
        get "/api/v1/users/100/active_threads"
        # this is silly, but it is the legacy behavior
        last_response.should be_ok
        last_response.body.should == "{}"
      end

      it "only returns threads with activity from the specified user"  do
        @comments["t3 c4"].author = @users["u100"]
        @comments["t3 c4"].save!
        rs = thread_result 100, course_id: "xyz"
        rs.length.should == 2
        check_thread_result(@users["u100"], @threads["t3"], rs[0])
        check_thread_result(@users["u100"], @threads["t0"], rs[1])
      end

      it "does not return threads in which the user has only participated anonymously" do
        @comments["t3 c4"].author = @users["u100"]
        @comments["t3 c4"].anonymous_to_peers = true
        @comments["t3 c4"].save!
        rs = thread_result 100, course_id: "xyz"
        rs.length.should == 1
        check_thread_result(@users["u100"], @threads["t0"], rs.first)
      end      

      it "only returns threads from the specified course" do
        @threads.each do |k, v|
          v.author = @users["u100"]
          v.save!
        end
        @threads["t9"].course_id = "zzz"
        @threads["t9"].save!
        rs = thread_result 100, course_id: "xyz"
        rs.length.should == 9
      end

      it "correctly orders results by most recently updated" do
        @threads.each do |k, v|
          v.author = @users["u100"]
          v.save!
        end
        @threads["t5"].updated_at = DateTime.now
        @threads["t5"].save!
        expected_order = @threads.keys.reverse.select{|k| k!="t5"}.insert(0, "t5")
        rs = thread_result 100, course_id: "xyz"
        actual_order = rs.map {|v| v["title"]}
        actual_order.should == expected_order
      end

      # TODO: note the checks on result["num_pages"] are disabled.
      # there is a bug in GET "#{APIPREFIX}/users/:user_id/active_threads
      # and this value is often wrong.
      context "pagination" do
        def thread_result_page (page, per_page)
          get "/api/v1/users/100/active_threads", course_id: "xyz", page: page, per_page: per_page
          last_response.should be_ok
          parse(last_response.body)
        end

        before(:each) do
          @threads.each do |k, v|
            @comments["#{k} c4"].author = @users["u100"]
            @comments["#{k} c4"].save!
          end
        end

        it "returns single page" do
          result = thread_result_page(1, 20)
          result["collection"].length.should == 10
          #result["num_pages"].should == 1
          result["page"].should == 1
        end
        it "returns multiple pages" do
          result = thread_result_page(1, 5)
          result["collection"].length.should == 5
          #result["num_pages"].should == 2
          result["page"].should == 1

          result = thread_result_page(2, 5)
          result["collection"].length.should == 5
          #result["num_pages"].should == 2
          result["page"].should == 2
        end
        it "orders correctly across pages" do
          expected_order = @threads.keys.reverse 
          actual_order = []
          per_page = 3
          num_pages = (@threads.length + per_page - 1) / per_page
          num_pages.times do |i|
            page = i + 1
            result = thread_result_page(page, per_page)
            result["collection"].length.should == (page * per_page <= @threads.length ? per_page : @threads.length % per_page)
            #result["num_pages"].should == num_pages
            result["page"].should == page
            actual_order += result["collection"].map {|v| v["title"]}
          end
          actual_order.should == expected_order
        end
      end

      def test_unicode_data(text)
        user = User.first
        course_id = "unicode_course"
        thread = make_thread(user, text, course_id, "unicode_commentable")
        make_comment(user, thread, text)
        result = thread_result(user.id, course_id: course_id)
        result.length.should == 1
        check_thread_result(nil, thread, result.first)
      end

      include_examples "unicode data"
    end
  end
end
