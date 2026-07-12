import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';
import { MasterDataService } from './master-data.service';
import { CreateSetTemplateDto } from './dto/create-template.dto';

@ApiTags('master-data')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('master-data')
export class MasterDataController {
  constructor(private svc: MasterDataService) {}

  @Get('templates') getTemplates() { return this.svc.getTemplates(); }
  @Get('sterilizers') getSterilizers() { return this.svc.getSterilizers(); }

  @Post('templates')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  createTemplate(@Body() dto: CreateSetTemplateDto, @Req() req: any) {
    return this.svc.createTemplate(dto, req.user.id);
  }
}
