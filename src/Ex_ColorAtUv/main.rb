require 'sketchup.rb'

module Example::ColorAtUv

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins').add_submenu(EXTENSION[:name])
    menu.add_item('Pick Color') { self.pick_color_tool }
    menu.add_separator
    menu.add_item('Help...') { self.open_help }
    file_loaded(__FILE__)
  end

  def self.pick_color_tool
    Sketchup.active_model.select_tool(ColorPickerTool.new)
  end


  class ColorPickerTool

    HUB_BACKGROUND = Sketchup::Color.new(0, 0, 0, 192).freeze
    HUB_BORDER = Sketchup::Color.new(0, 0, 0).freeze

    def initialize
      @pick_data = nil
      @hud_position = ORIGIN
    end

    def activate
      initialize
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @pick_data = pick_color(x, y, view)
      @hud_position = Geom::Point3d.new(x, y)
      view.invalidate
    end

    def draw(view)
      return if @pick_data.nil?
      x, y = @hud_position.to_a
      view.line_stipple = ''
      # Draw the background:
      draw_rectangle_filled(view, x - 15, y - 15, -150, -150, HUB_BACKGROUND)
      draw_rectangle(view, x - 15, y - 15, -150, -150, HUB_BORDER)
      # Draw the picked color:
      color = @pick_data[:color]
      draw_rectangle_filled(view, x - 25, y - 25, -130, -130, color)
      draw_rectangle(view, x - 25, y - 25, -130, -130, HUB_BORDER)
      # Draw leader:
      view.draw2d(GL_LINES, [[x - 1, y - 1, 0], [x - 15, y -15, 0]])
      # Draw color values:
      tx = x - 15 - 75
      ty = y - 15 - 150 - 18
      text = "RGBA: %d, %d, %d, %d" % color.to_a
      options = {
        :font => "Arial",
        :size => 10,
        :bold => true,
        :align => TextAlignCenter,
      }
      view.draw_text([tx, ty, 0], text, options)
      # Draw color names:
      name = find_color_name(color)
      unless name.nil?
        tx = x - 15 - 75
        ty = y - 10
        options = {
          :font => "Arial",
          :size => 10,
          :bold => true,
          :align => TextAlignCenter,
        }
        view.draw_text([tx, ty, 0], %("#{name}"), options)
      end
      # Draw UV values:
      uv = @pick_data[:uv]
      unless uv.nil?
        tx = x
        ty = y - 25
        options = {
          :font => "Arial",
          :size => 10,
          :bold => true,
          :align => TextAlignLeft,
        }
        text = "UV: %.4f, %.4f" % uv.to_a.first(2)
        view.draw_text([tx, ty, 0], text, options)
      end
    end

    private

    def build_color_cache
      cache = {}
      Sketchup::Color.names.each { |name|
        color = Sketchup::Color.new(name)
        cache[color.to_a] = name
      }
      cache
    end

    def find_color_name(color)
      @@names ||= build_color_cache
      @@names[color.to_a]
    end

    def draw_rectangle_filled(view, x, y, width, height, color)
      points = [
        Geom::Point3d.new(x, y, 0),
        Geom::Point3d.new(x + width, y, 0),
        Geom::Point3d.new(x + width, y + height, 0),
        Geom::Point3d.new(x, y + height, 0),
      ]
      view.drawing_color = color
      view.draw2d(GL_QUADS, points)
    end

    def draw_rectangle(view, x, y, width, height, color, line_width = 1)
      points = [
        Geom::Point3d.new(x, y, 0),
        Geom::Point3d.new(x + width, y, 0),
        Geom::Point3d.new(x + width, y + height, 0),
        Geom::Point3d.new(x, y + height, 0),
      ]
      if line_width % 2 != 0
        # Offset odd pixel line-width with half a pixel in order to ensure they
        # draw crisp and sharp.
        tr = Geom::Transformation.new(Geom::Vector3d.new(0.5, 0.5, 0.0))
        points.each { |point| point.transform!(tr) }
      end
      view.line_width = line_width
      view.drawing_color = color
      view.draw2d(GL_LINE_LOOP, points)
    end

    # The alpha channels in the colors used in materials are junk. It is ignored
    # and instead the alpha property of the material itself is used.
    # Some times the color alpha can be 0 while the material alpha is 1.0.
    # So we must extract this from both properties.
    # TODO: Add note in documentation about this unexpected behaviour.
    def get_material_color(material)
      r, g, b = material.color.to_a
      a = 255 * material.alpha
      Sketchup::Color.new(r, g, b, a)
    end

    def pick_color(x, y, view)
      ray = view.pickray(x, y)
      global_point, instance_path = view.model.raytest(ray, true)
      return nil if global_point.nil?
      # The point is the world position where the pick hit something.
      # The instance path is an array that contains the entity that was hit,
      # last in the array, and the instances that contains it.
      face = instance_path.pop
      return nil unless face.is_a?(Sketchup::Face)
      # Determine if we picked the front or backside.
      front = face.normal.dot(ray[1]) < 0.0
      material = front ? face.material : face.back_material
      return nil if material.nil?
      # We simply return the material color when the material have no texture.
      return { color: get_material_color(material) } if material.texture.nil?
      # Using the picked point and the picked entity we can resolve the UV
      # coordinate picked.
      # First we must translate the globally picked point to the local space for
      # the face.
      # TODO: Double check the order of transformations multiplied is correct.
      to_global = instance_path.inject(IDENTITY) { |tr, instance|
        # The inject method will yield the result of the previous iteration in
        # the first parameter of the block; here "tr".
        # This accumulate the total transformation for all the instances in the
        # instance path.
        instance.transformation * tr
      }
      to_local = to_global.inverse
      local_point = global_point.transform(to_local)
      # Fetch a UVHelper for the front and backside.
      uvh = face.get_UVHelper(true, true)
      uvq = front ? uvh.get_front_UVQ(local_point) : uvh.get_back_UVQ(local_point)
      # Need to convert from UVQ to UV.
      u = uvq.x / uvq.z
      v = uvq.y / uvq.z
      image_rep = material.texture.image_rep
      {
        color: image_rep.color_at_uv(u, v),
        uv: [u, v],
        global_point: global_point,
        local_point: local_point,
      }
    end

  end # class


  def self.open_help
    UI.openURL(EXTENSION[:url])
  end

end # module
