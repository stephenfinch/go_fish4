require "rack/test"
require "rspec"
require "pry"
require "selenium/webdriver"
require "webdrivers/chromedriver"
require "capybara"
require "capybara/dsl"
ENV["RACK_ENV"] = "test"
require "../server"
require "../lib/playing_card"

RSpec.describe Server do
  # include Rack::Test::Methods
  include Capybara::DSL

  def make_sessions_join(num, selenium = false)
    num.times.map do |index|
      session = selenium ? Capybara::Session.new(:selenium_chrome_headless, Server.new) : Capybara::Session.new(:rack_test, Server.new)
      session.visit "/"
      session.fill_in :name, with: "Player #{index + 1}"
      session.click_on "Join"
      session
    end
  end

  def refresh_given_sessions(sessions)
    sessions.each do |session|
      session.visit(session.current_url)
    end
  end

  def session_start_turn(session)
    session.click_on "Start"
    session.click_on "Try and Take Turn"
  end

  def session_take_turn(session)
    session_start_turn(session)
    pick_first_option(session)
  end

  def pick_first_option(session)
    session.choose(id: "card0", name: "playingcard")
    session.choose(id: "player0", name: "player_id")
    session.click_on "Ask"
  end

  def reset_hands
    game.players.each do |player|
      player.hand = []
    end
  end

  def give_cards(cards)
    game.players.each do |player|
      player.take_cards(cards)
    end
  end

  def choose_correct_card(session)
    reset_hands
    give_cards([PlayingCard.new("A")])
    refresh_given_sessions([session])
    pick_first_option(session)
  end

  def choose_incorrect_card(session)
    reset_hands
    turn_player.take_cards([PlayingCard.new("A")])
    refresh_given_sessions([session])
    pick_first_option(session)
  end

  let(:game) { Server.game }
  let(:turn_player) { game.turn_player }

  before(:each) do
    Capybara.app = Server.new
    Capybara.server = :webrick
  end

  after(:each) do
    Server.reset_game
  end

  it "is possible to join a game" do
    visit "/"
    fill_in :name, with: "John"
    click_on "Join"
    expect(page).to have_content("Players")
    expect(page).to have_content("John")
  end

  it "allows multiple players to join game" do
    session1, session2 = make_sessions_join(2)
    expect(session1).to have_css("strong", text: "Player")
    expect(session2).to have_css("strong", text: "Player")
    expect(session2).to have_content("Player 1")
    refresh_given_sessions([session1, session2])
    expect(session1).to have_content("Player 2")
  end

  it "lets player1 take turn" do
    session1, session2 = make_sessions_join(2)
    refresh_given_sessions([session1, session2])
    session_start_turn(session1)
    expect(session1).to have_content("Your Turn")
  end

  it "lets player2 take turn after player1" do
    session1, session2 = make_sessions_join(2)
    # binding.pry
    session_start_turn(session1)
    choose_incorrect_card(session1)
    session_start_turn(session2)
    expect(session2).to have_content("Your Turn")
  end

  it "shows the turn player that they have 0 books at the start" do
    session1, session2 = make_sessions_join(2)
    refresh_given_sessions([session1, session2])
    session_start_turn(session1)
    expect(session1).to have_content("0 books")
  end

  it "shows the turn player how many books they have" do
    session1, session2 = make_sessions_join(2)
    reset_hands
    game.turn_player.take_cards([PlayingCard.new("K"), PlayingCard.new("K"), PlayingCard.new("K"), PlayingCard.new("K")])
    session_start_turn(session1)
    expect(session1).to have_content("1 books")
  end

  it "deals 5 cards at the start of the game" do
    session1, session2 = make_sessions_join(2)
    expect(turn_player.cards_left).to eq 5
  end

  it "shows the turn player cards in their hand" do
    session1, session2 = make_sessions_join(2)
    refresh_given_sessions([session1, session2])
    session_start_turn(session1)
    expect(session1).to have_field("#{turn_player.hand.first.rank}")
    expect(session1).to have_field("#{turn_player.hand.last.rank}")
  end

  it "shows the turn player the other players they can pick" do
    session1, session2 = make_sessions_join(2)
    refresh_given_sessions([session1, session2])
    session_start_turn(session1)
    expect(session1).to have_field("#{game.players.last.name}")
  end

  it "shows the turn player the other players they can pick" do
    session1, session2 = make_sessions_join(2)
    refresh_given_sessions([session1, session2])
    session_start_turn(session1)
    expect(session1).to_not have_field("#{turn_player.name}")
  end

  it "goes to results page after asking" do
    session1, session2 = make_sessions_join(2)
    session_start_turn(session1)
    pick_first_option(session1)
    expect(session1).to have_content("You asked")
  end

  it "tells the turn player to Go Fish if they didnt get a card back" do
    session1, session2 = make_sessions_join(2)
    session_start_turn(session1)
    choose_incorrect_card(session1)
    expect(session1).to have_content("Go Fish")
  end

  it "tells the turn player how many cards they fished if they ask for a correct card" do
    session1, session2 = make_sessions_join(2)
    session_start_turn(session1)
    choose_correct_card(session1)
    expect(session1).to have_content("received 1")
  end

  it "removes cards from other players hand if they were fished" do
    session1, session2 = make_sessions_join(2)
    session_start_turn(session1)
    choose_correct_card(session1)
    expect(game.players.last.hand).to eq []
  end

  it "draws a card from the deck if you didnt fish a card" do
    session1, session2 = make_sessions_join(2)
    session_start_turn(session1)
    choose_incorrect_card(session1)
    expect(turn_player.hand.length).to eq 2
    expect(game.deck.cards_left).to eq 41
  end

  it "lets you go again if you fished a card" do
    session1, session2 = make_sessions_join(2)
    session_start_turn(session1)
    choose_correct_card(session1)
    session1.click_on "Go Again"
    expect(session1).to have_content("Your Turn")
  end

  it "shows all results after someone takes a turn" do
    session1, session2 = make_sessions_join(2)
    session_start_turn(session1)
    choose_incorrect_card(session1)
  end

  xcontext "pusher tests" do
    it "uses JS to refresh the page", :js do
      session1, session2 = make_sessions_join(2, true)
      expect(session2).to have_content("Players")
      expect(session2).to have_content("Player 2")
      expect(session1).to have_content("Players")
      expect(session1).to have_content("Player 2")
    end
  end
end