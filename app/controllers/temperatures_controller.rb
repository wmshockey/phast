class TemperaturesController < ApplicationController
    before_action :set_temperature, only: [:show, :edit, :update, :destroy]

    # GET /temperatures
    # GET /temperatures.json
    def index
      @pipeline = Pipeline.find(params[:pipeline_id])
      @temperatures = @pipeline.temperatures.all
    end

    # GET /temperatures/1
    # GET /temperatures/1.json
    def show
    end

    # GET /temperatures/new
    def new
      @pipeline = Pipeline.find(params[:pipeline_id])
      @temperature = @pipeline.temperatures.build
    end

    # GET /temperatures/1/edit
    def edit
    end

    # POST /temperatures
    # POST /temperatures.json
    def create
      @pipeline = Pipeline.find(params[:pipeline_id])
      @temperature = @pipeline.temperatures.new(temperature_params)

      respond_to do |format|
        if @temperature.save
          format.html { redirect_to new_pipeline_temperature_path(@pipeline), notice: 'Temperature was successfully created.' }
          format.json { render :show, status: :created, location: @temperature }
        else
          format.html { render :new }
          format.json { render json: @temperature.errors, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /temperatures/1
    # PATCH/PUT /temperatures/1.json
    def update
      respond_to do |format|
        if @temperature.update(temperature_params)
          format.html { redirect_to pipeline_path(@pipeline), notice: 'Temperature was successfully updated.' }
          format.json { render :show, status: :ok, location: @temperature }
        else
          format.html { render :edit }
          format.json { render json: @temperature.errors, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /temperatures/1
    # DELETE /temperatures/1.json
    def destroy
        respond_to do |format|
          if @temperature.destroy
            format.html { redirect_to pipeline_path(@pipeline), notice: 'Temperature was successfully deleted.' }
            format.json { render :show, status: :destroyed, location: @pipeline }
          else
            format.html { render :delete }
            format.json { render json: @temperature.errors, status: :unprocessable_entity }
          end
        end
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_temperature
        @pipeline = Pipeline.find(params[:pipeline_id])
        @temperature = @pipeline.temperatures.find(params[:id])
      end

      # Never trust parameters from the scary internet, only allow the white list through.
      def temperature_params
        params.require(:temperature).permit(:id, :kmp, :temperature)
      end

end
